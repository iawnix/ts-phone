import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ServerConfig } from "../src/config.js";
import { createTsPhoneHttpServer } from "../src/http-server.js";
import { readBearerToken } from "../src/security.js";
import { connectFakeBridge, type FakeBridge } from "./helpers.js";

const ZERO_REVISION = "00000000-0000-0000-0000-000000000000";

test("HTTP API keeps an offline workspace read-only until its TSPi bridge connects", async () => {
  const fixture = await startFixture();
  try {
    const unauthorized = await fetch(`${fixture.baseUrl}/api/v4/workspaces`);
    assert.equal(unauthorized.status, 401);

    const versionResponse = await api(fixture, "/api/v4/version");
    assert.equal(versionResponse.status, 200);
    const version = await versionResponse.json() as {
      data: { apiVersion: string; serviceVersion: string };
    };
    assert.deepEqual(version.data, {
      apiVersion: "ts-phone-api/4",
      serviceVersion: "0.7.0",
    });
    assert.equal((await api(fixture, "/api/v3/version")).status, 404);

    const offline = await api(fixture, "/api/v4/workspaces");
    assert.equal(offline.status, 200);
    assert.match(await offline.text(), /offline/);

    const rejected = await sendPrompt(fixture, "offline-message", "offline");
    assert.equal(rejected.status, 404);

    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    const sessions = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    const sessionsPayload = await sessions.json() as {
      data: Array<SessionListItem & {
        runtime?: {
          model: { provider: string; id: string };
          context?: { usedTokens: number | null; limitTokens: number };
        };
      }>;
    };
    assert.equal(sessionsPayload.data[0]?.runtime?.model.id, "fake-model");
    assert.equal(sessionsPayload.data[0]?.runtime?.context?.usedTokens, 78_214);
    assert.equal(sessionsPayload.data[0]?.runtime?.context?.limitTokens, 128_000);
    fixture.bridge.publishSnapshot(false, false);
    await waitFor(async () => {
      const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
      const payload = await response.json() as { data: Array<{ runtime?: unknown }> };
      return payload.data[0]?.runtime === undefined;
    }, true);
    const accepted = await sendPrompt(fixture, "message-1", "hello");
    assert.equal(accepted.status, 202);
    const duplicate = await sendPrompt(fixture, "message-1", "hello");
    assert.equal(duplicate.status, 202);
    assert.equal(fixture.bridge.receivedCommands.filter((item) => item.type === "command.prompt").length, 1);
    await waitForMessages(fixture, "reply:hello");
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("service restart restores disk history as a read-only session", async () => {
  const fixture = await startFixture();
  const sessionId = "session-history";
  const sessionFile = await writePersistedHistory(fixture.workspace, sessionId, [
    {
      role: "user",
      content: [{ type: "text", text: "historical prompt" }],
      timestamp: 1,
    },
    {
      role: "assistant",
      provider: "private-provider",
      usage: { private: true },
      content: [
        { type: "thinking", thinking: "private reasoning" },
        { type: "text", text: "historical reply" },
      ],
      timestamp: 2,
    },
  ]);
  await restartFixture(fixture);
  try {
    const sessionsResponse = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    assert.equal(sessionsResponse.status, 200);
    const sessionsPayload = await sessionsResponse.json() as {
      data: Array<SessionListItem & {
        runtimeState: string;
        historyAvailable: boolean;
        historyOnly: boolean;
        canPrompt: boolean;
        sessionName?: string;
        updatedAt?: string;
      }>;
    };
    assert.deepEqual(sessionsPayload.data.map((session) => session.sessionId), [sessionId]);
    const restored = sessionsPayload.data[0]!;
    assert.equal(restored.runtimeState, "offline");
    assert.equal(restored.historyAvailable, true);
    assert.equal(restored.historyOnly, true);
    assert.equal(restored.canPrompt, false);
    assert.equal(restored.sessionName, "historical prompt");
    assert.ok(restored.updatedAt && Number.isFinite(Date.parse(restored.updatedAt)));
    assert.deepEqual(restored.capabilities, [
      "history.messages",
      "activity.tools",
      "history.timeline",
      "history.pagination",
      "history.branches",
      "activity.subagents",
      "activity.research",
    ]);

    const snapshotResponse = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages`,
    );
    assert.equal(snapshotResponse.status, 200);
    const snapshotText = await snapshotResponse.text();
    assert.match(snapshotText, /historical prompt/);
    assert.match(snapshotText, /historical reply/);
    assert.doesNotMatch(snapshotText, /private-provider|private reasoning|usage/);

    const timelineResponse = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/timeline?limit=1`,
    );
    assert.equal(timelineResponse.status, 200);
    const timelinePayload = await timelineResponse.json() as {
      data: {
        schemaVersion: string;
        items: Array<{ id: string }>;
        history: { totalItems: number; messageCount: number; turnCount: number };
        hasMore: boolean;
        nextBefore?: string;
      };
    };
    assert.equal(timelinePayload.data.schemaVersion, "ts-phone-timeline/1");
    assert.equal(timelinePayload.data.items.length, 1);
    assert.equal(timelinePayload.data.history.totalItems, 2);
    assert.equal(timelinePayload.data.history.messageCount, 2);
    assert.equal(timelinePayload.data.history.turnCount, 1);
    assert.equal(timelinePayload.data.hasMore, true);
    assert.equal(timelinePayload.data.nextBefore, timelinePayload.data.items[0]!.id);

    const invalidTimelineQuery = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/timeline?unknown=true`,
    );
    assert.equal(invalidTimelineQuery.status, 400);
    assert.match(await invalidTimelineQuery.text(), /invalid_timeline_query/);

    const promptResponse = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          clientMessageId: "offline-prompt",
          sessionRevision: restored.sessionRevision,
          message: "must not run",
        }),
      },
    );
    assert.equal(promptResponse.status, 409);
    assert.match(await promptResponse.text(), /session_offline/);

    await rm(sessionFile);
    const afterDelete = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    const afterDeletePayload = await afterDelete.json() as { data: unknown[] };
    assert.deepEqual(afterDeletePayload.data, []);
  } finally {
    await fixture.application.close();
  }
});

test("a live timeline exposes commands only on its active branch", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    const records = [{
      type: "session",
      version: 3,
      id: "session-test",
      timestamp: new Date().toISOString(),
      cwd: fixture.workspace,
    }, {
      type: "message",
      id: "00000001",
      parentId: null,
      message: { role: "user", content: "root", timestamp: 1 },
    }, {
      type: "message",
      id: "00000002",
      parentId: "00000001",
      message: { role: "assistant", content: "inactive", timestamp: 2 },
    }, {
      type: "message",
      id: "00000003",
      parentId: "00000001",
      message: { role: "assistant", content: "active", timestamp: 3 },
    }];
    await writeFile(
      fixture.bridge.sessionFile,
      `${records.map((record) => JSON.stringify(record)).join("\n")}\n`,
    );

    const activeResponse = await api(
      fixture,
      "/api/v4/workspaces/ts_001/sessions/session-test/timeline",
    );
    assert.equal(activeResponse.status, 200);
    const active = await activeResponse.json() as {
      data: { capabilities: string[]; history: { selectedBranchId?: string } };
    };
    assert.equal(active.data.history.selectedBranchId, "00000003");
    assert.equal(active.data.capabilities.includes("command.prompt"), true);
    assert.equal(active.data.capabilities.includes("command.abort"), true);

    const inactiveResponse = await api(
      fixture,
      "/api/v4/workspaces/ts_001/sessions/session-test/timeline?branch=00000002",
    );
    assert.equal(inactiveResponse.status, 200);
    const inactive = await inactiveResponse.json() as {
      data: { capabilities: string[]; history: { selectedBranchId?: string } };
    };
    assert.equal(inactive.data.history.selectedBranchId, "00000002");
    assert.equal(inactive.data.capabilities.includes("command.prompt"), false);
    assert.equal(inactive.data.capabilities.includes("command.abort"), false);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("message history pages use stable Pi entry cursors", async () => {
  const fixture = await startFixture();
  const sessionId = "session-paged";
  await writePersistedHistory(
    fixture.workspace,
    sessionId,
    Array.from({ length: 505 }, (_, index) => assistantMessage(`history-${index}`)),
  );
  await restartFixture(fixture);
  try {
    const latest = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages?limit=3`,
    );
    assert.equal(latest.status, 200);
    const latestPayload = await latest.json() as {
      data: MessageSnapshotResponse & { messageIds: string[]; hasMore: boolean; nextBefore?: string };
    };
    assert.deepEqual(latestPayload.data.messageIds, ["000001f6", "000001f7", "000001f8"]);
    assert.equal(latestPayload.data.hasMore, true);
    assert.equal(latestPayload.data.nextBefore, "000001f6");
    assert.match(JSON.stringify(latestPayload.data.messages), /history-502/);

    const earlier = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages?before=000001f6&limit=2`,
    );
    assert.equal(earlier.status, 200);
    const earlierPayload = await earlier.json() as {
      data: MessageSnapshotResponse & { messageIds: string[]; hasMore: boolean; nextBefore?: string };
    };
    assert.deepEqual(earlierPayload.data.messageIds, ["000001f4", "000001f5"]);
    assert.equal(earlierPayload.data.nextBefore, "000001f4");

    const unknown = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages?before=ffffffff`,
    );
    assert.equal(unknown.status, 409);
    assert.match(await unknown.text(), /session_history_cursor_invalid/);

    const malformed = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages?before=not-a-cursor`,
    );
    assert.equal(malformed.status, 400);
    assert.match(await malformed.text(), /invalid_message_cursor/);
  } finally {
    await fixture.application.close();
  }
});

test("a live bridge takes over the matching disk-history session", async () => {
  const fixture = await startFixture();
  const sessionId = "session-overlay";
  await writePersistedHistory(fixture.workspace, sessionId, [assistantMessage("disk reply")]);
  try {
    const before = await waitForSessionCount(fixture, 1);
    assert.equal(before[0]?.sessionId, sessionId);
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace, {
      sessionId,
      accessMode: "controller",
    });
    await waitFor(async () => {
      const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
      const payload = await response.json() as {
        data: Array<SessionListItem & { canPrompt: boolean; historyOnly: boolean }>;
      };
      return payload.data[0]?.canPrompt === true && payload.data[0]?.historyOnly === false;
    }, true);
    const liveSnapshot = await api(
      fixture,
      `/api/v4/workspaces/ts_001/sessions/${sessionId}/messages`,
    );
    assert.equal(liveSnapshot.status, 200);
    assert.match(await liveSnapshot.text(), /existing/);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("SSE publishes CLI input and replays only events after Last-Event-ID", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    const journal = await fixture.application.hub.journal("ts_001", "session-test");
    const firstId = journal.since(undefined).at(-1)?.id;
    assert.ok(firstId);

    fixture.bridge.publish("input", {
      type: "input",
      text: "CLI prompt",
      source: "interactive",
      origin: "local",
    });
    const replay = await fetch(`${fixture.baseUrl}/api/v4/workspaces/ts_001/sessions/session-test/events`, {
      headers: { ...fixture.headers, "Last-Event-ID": firstId },
    });
    const replayReader = replay.body!.getReader();
    const record = await readSseRecord(replayReader);
    assert.match(record, /event: input/);
    assert.match(record, /"instanceEpoch":"11111111/);
    await replayReader.cancel();
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("message snapshots checkpoint completed assistant and tool messages before agent settles", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    fixture.bridge.publish("agent_start", { type: "agent_start", agentRunId: "run-1-11" });
    fixture.bridge.publish("message_end", {
      type: "message_end",
      message: assistantMessage("checkpoint reply"),
    });
    fixture.bridge.publish("message_end", {
      type: "message_end",
      message: toolResultMessage("tool output"),
    });

    const snapshot = await waitForSnapshot(fixture, 3);
    assert.deepEqual(snapshot.messages.map(messageRole), ["user", "assistant", "toolResult"]);
    assert.match(JSON.stringify(snapshot.messages), /checkpoint reply/);
    assert.match(JSON.stringify(snapshot.messages), /tool output/);
    const journal = await fixture.application.hub.journal("ts_001", "session-test");
    const events = journal.since(undefined);
    const originalSnapshot = events.find((event) => event.type === "session.snapshot");
    assert.equal((originalSnapshot?.payload as { messages: unknown[] }).messages.length, 1);
    const lastMessageEnd = events.filter((event) => event.type === "message_end").at(-1);
    assert.equal(snapshot.lastEventId, lastMessageEnd?.id);
    await waitForState(fixture, "running");
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("message snapshots remain bounded while a long turn is still running", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    fixture.bridge.publish("agent_start", { type: "agent_start", agentRunId: "run-1-12" });
    for (let index = 0; index < 510; index += 1) {
      fixture.bridge.publish("message_end", {
        type: "message_end",
        message: assistantMessage(`bounded-${index}`),
      });
    }

    const snapshot = await waitForSnapshot(fixture, 500);
    assert.equal(snapshot.messages.length, 500);
    assert.match(JSON.stringify(snapshot.messages[0]), /bounded-10/);
    assert.match(JSON.stringify(snapshot.messages.at(-1)), /bounded-509/);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("session snapshot events publish the same bounded history as the API", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    for (let index = 0; index < 510; index += 1) {
      fixture.bridge.messages.push(assistantMessage(`bridge-snapshot-${index}`));
    }
    fixture.bridge.publishSnapshot();

    const journal = await fixture.application.hub.journal("ts_001", "session-test");
    await waitFor(async () => {
      const latest = journal.since(undefined)
        .filter((event) => event.type === "session.snapshot")
        .at(-1);
      return JSON.stringify(latest?.payload).includes("bridge-snapshot-509");
    }, true);
    const latest = journal.since(undefined)
      .filter((event) => event.type === "session.snapshot")
      .at(-1);
    const messages = (latest?.payload as { messages: unknown[] }).messages;
    const runtime = (latest?.payload as {
      runtime?: { model: { id: string }; context?: { usedTokens: number | null } };
    }).runtime;
    assert.equal(messages.length, 500);
    assert.equal(runtime?.model.id, "fake-model");
    assert.equal(runtime?.context?.usedTokens, 78_214);
    assert.match(JSON.stringify(messages[0]), /bridge-snapshot-10/);
    assert.match(JSON.stringify(messages.at(-1)), /bridge-snapshot-509/);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("SSE subscribes before replay so an event at the replay boundary is delivered once", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    const snapshot = await readSnapshot(fixture);
    const journal = await fixture.application.hub.journal("ts_001", "session-test");
    const originalSince = journal.since.bind(journal);
    let injected = false;
    journal.since = (lastEventId) => {
      const replay = originalSince(lastEventId);
      if (!injected) {
        injected = true;
        journal.publish("replay_boundary", { marker: "delivered-once" });
      }
      return replay;
    };

    const response = await fetch(`${fixture.baseUrl}/api/v4/workspaces/ts_001/sessions/session-test/events`, {
      headers: { ...fixture.headers, "Last-Event-ID": snapshot.lastEventId },
      signal: AbortSignal.timeout(2_000),
    });
    const reader = response.body!.getReader();
    const record = await readSseRecord(reader);
    assert.equal(record.match(/delivered-once/g)?.length, 1);
    assert.match(record, /event: replay_boundary/);
    await reader.cancel();
    journal.since = originalSince;
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("phone approval responses are fenced to a live workspace session", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    fixture.bridge.requestApproval({
      approvalId: "approval-1",
      turnId: "turn-1",
      toolCallId: "tool-1",
      toolName: "bash",
      preview: "Tool: bash\n\ncommand: pwd",
    });
    const journal = await fixture.application.hub.journal("ts_001", "session-test");
    await waitFor(
      async () => journal.since(undefined).some((event) => event.type === "approval.request"),
      true,
    );
    const approvalEvent = journal.since(undefined).find((event) => event.type === "approval.request");
    assert.deepEqual(approvalEvent?.payload, {
      id: "approval-1",
      method: "confirm",
      message: "Tool: bash\n\ncommand: pwd",
      preview: "Tool: bash\n\ncommand: pwd",
      toolName: "bash",
      turnId: "turn-1",
      toolCallId: "tool-1",
      expiresAt: (approvalEvent?.payload as { expiresAt: string }).expiresAt,
    });
    await waitFor(async () => {
      const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions/session-test/approvals/approval-1", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ approved: true, sessionRevision: await currentRevision(fixture) }),
      });
      return response.status;
    }, 202);
    assert.equal(
      fixture.bridge.receivedCommands.some((item) => item.type === "approval.respond" && item.approved === true),
      true,
    );
    const replay = await api(fixture, "/api/v4/workspaces/ts_001/sessions/session-test/approvals/approval-1", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ approved: true, sessionRevision: await currentRevision(fixture) }),
    });
    assert.equal(replay.status, 404);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("disconnecting during a running turn requires recovery", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    fixture.bridge.publish("agent_start", { type: "agent_start", agentRunId: "run-1-13" });
    await waitForState(fixture, "running");
    await fixture.bridge.close();
    await waitForState(fixture, "recovery_required");
    const sessions = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    const payload = await sessions.json() as {
      data: Array<{ runtime?: { model: { id: string }; updatedAt: string } }>;
    };
    assert.equal(payload.data[0]?.runtime?.model.id, "fake-model");
    assert.equal(payload.data[0]?.runtime?.updatedAt, "2026-08-31T06:32:18.000Z");
  } finally {
    await fixture.application.close();
  }
});

test("abort is fenced to the exact active agent run", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    const sessionRevision = await currentRevision(fixture);
    const abortPath = "/api/v4/workspaces/ts_001/sessions/session-test/abort";

    const missingRun = await api(fixture, abortPath, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionRevision }),
    });
    assert.equal(missingRun.status, 400);
    assert.match(await missingRun.text(), /invalid_abort/);

    const extraField = await api(fixture, abortPath, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionRevision, agentRunId: "run-1-20", force: true }),
    });
    assert.equal(extraField.status, 400);
    assert.match(await extraField.text(), /invalid_abort/);

    const idle = await api(fixture, abortPath, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionRevision, agentRunId: "run-1-20" }),
    });
    assert.equal(idle.status, 409);
    assert.match(await idle.text(), /agent_not_running/);
    assert.equal(fixture.bridge.receivedCommands.some((item) => item.type === "command.abort"), false);

    const replacedAgentRunId = "run-1-20";
    fixture.bridge.publish("agent_start", {
      type: "agent_start",
      agentRunId: replacedAgentRunId,
    });
    await waitForState(fixture, "running");
    fixture.bridge.publish("agent_settled", {
      type: "agent_settled",
      agentRunId: replacedAgentRunId,
    });
    await waitForState(fixture, "idle");

    const agentRunId = "run-1-21";
    fixture.bridge.publish("agent_start", { type: "agent_start", agentRunId });
    await waitForState(fixture, "running");
    const sessionsResponse = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    const sessions = await sessionsResponse.json() as {
      data: Array<{ activeAgentRunId: string | null }>;
    };
    assert.equal(sessions.data[0]?.activeAgentRunId, agentRunId);
    const activeSnapshot = await readSnapshot(fixture);
    assert.equal(activeSnapshot.activeAgentRunId, agentRunId);
    const activeJournal = await fixture.application.hub.journal("ts_001", "session-test");
    assert.equal(
      activeJournal.since(activeSnapshot.lastEventId).some((event) => (
        event.type === "agent_start" || event.type === "agent_settled"
      )),
      false,
    );
    const timelineResponse = await api(
      fixture,
      "/api/v4/workspaces/ts_001/sessions/session-test/timeline",
    );
    assert.equal(timelineResponse.status, 200);
    const timeline = await timelineResponse.json() as {
      data: { activeAgentRunId: string | null };
    };
    assert.equal(timeline.data.activeAgentRunId, agentRunId);

    const stale = await api(fixture, abortPath, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionRevision, agentRunId: replacedAgentRunId }),
    });
    assert.equal(stale.status, 409);
    assert.match(await stale.text(), /agent_run_stale/);
    assert.equal(fixture.bridge.receivedCommands.some((item) => item.type === "command.abort"), false);

    const accepted = await api(fixture, abortPath, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionRevision, agentRunId }),
    });
    assert.equal(accepted.status, 200);
    await waitForState(fixture, "idle");
    const command = fixture.bridge.receivedCommands.find((item) => item.type === "command.abort");
    assert.equal(command?.agentRunId, agentRunId);
    assert.equal((await readSnapshot(fixture)).activeAgentRunId, null);

    const journal = await fixture.application.hub.journal("ts_001", "session-test");
    const runEvents = journal.since(undefined).filter((event) => (
      event.type === "agent_start" || event.type === "agent_settled"
    ));
    assert.deepEqual(
      runEvents.map((event) => (event.payload as { agentRunId?: string }).agentRunId),
      [replacedAgentRunId, replacedAgentRunId, agentRunId, agentRunId],
    );
    const stateEvents = journal.since(undefined).filter((event) => event.type === "session_state");
    assert.equal(stateEvents.some((event) => (
      (event.payload as { activeAgentRunId?: string | null }).activeAgentRunId === agentRunId
    )), true);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("bridge abort rejections retain their conflict codes", async () => {
  for (const errorCode of ["agent_not_running", "agent_run_stale"] as const) {
    const fixture = await startFixture();
    try {
      fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace, {
        abortErrorCode: errorCode,
      });
      await waitForState(fixture, "idle");
      const agentRunId = `run-1-${errorCode === "agent_not_running" ? 31 : 32}`;
      fixture.bridge.publish("agent_start", { type: "agent_start", agentRunId });
      await waitForState(fixture, "running");

      const response = await api(
        fixture,
        "/api/v4/workspaces/ts_001/sessions/session-test/abort",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            sessionRevision: await currentRevision(fixture),
            agentRunId,
          }),
        },
      );
      assert.equal(response.status, 409);
      assert.match(await response.text(), new RegExp(errorCode));
    } finally {
      await fixture.bridge?.close();
      await fixture.application.close();
    }
  }
});

test("deleting a persisted Pi session removes its disconnected broker record", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");
    await rm(fixture.bridge.sessionFile);
    const live = await waitForSessionCount(fixture, 1);
    assert.equal(live[0]?.sessionId, "session-test");

    await fixture.bridge.close();
    const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    assert.equal(response.status, 200);
    const payload = await response.json() as { data: SessionListItem[] };
    assert.deepEqual(payload.data, []);
  } finally {
    await fixture.application.close();
  }
});

test("deleting and recreating a workspace cannot revive stale broker sessions", async () => {
  const fixture = await startFixture();
  try {
    fixture.bridge = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace);
    await waitForState(fixture, "idle");

    await rm(fixture.workspace, { recursive: true });
    const removedResponse = await api(fixture, "/api/v4/workspaces");
    const removed = await removedResponse.json() as { data: unknown[] };
    assert.deepEqual(removed.data, []);

    await mkdir(fixture.workspace, { recursive: true });
    const recreatedResponse = await api(fixture, "/api/v4/workspaces");
    const recreated = await recreatedResponse.json() as {
      data: Array<{ sessionCount: number; liveSessionCount: number }>;
    };
    assert.equal(recreated.data[0]?.sessionCount, 0);
    assert.equal(recreated.data[0]?.liveSessionCount, 0);
  } finally {
    await fixture.bridge?.close();
    await fixture.application.close();
  }
});

test("one workspace isolates multiple live sessions and keeps one controller", async () => {
  const fixture = await startFixture();
  let controller: FakeBridge | undefined;
  let observer: FakeBridge | undefined;
  try {
    controller = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace, {
      sessionId: "session-controller",
      accessMode: "controller",
      instanceEpoch: "11111111-1111-4111-8111-111111111111",
    });
    observer = await connectFakeBridge(fixture.config, "ts_001", fixture.workspace, {
      sessionId: "session-observer",
      accessMode: "observer",
      instanceEpoch: "22222222-2222-4222-8222-222222222222",
    });

    const sessions = await waitForSessionCount(fixture, 2);
    assert.deepEqual(
      sessions.map((session) => [session.sessionId, session.accessMode]),
      [["session-controller", "controller"], ["session-observer", "observer"]],
    );
    const observerSession = sessions.find((session) => session.sessionId === "session-observer")!;
    const response = await api(
      fixture,
      "/api/v4/workspaces/ts_001/sessions/session-observer/messages",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          clientMessageId: "observer-message-1",
          sessionRevision: observerSession.sessionRevision,
          message: "observer question",
        }),
      },
    );
    assert.equal(response.status, 202);
    await waitFor(() => observer!.receivedCommands.filter((item) => item.type === "command.prompt").length, 1);
    assert.equal(controller.receivedCommands.some((item) => item.type === "command.prompt"), false);

    const stale = await api(
      fixture,
      "/api/v4/workspaces/ts_001/sessions/session-observer/abort",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sessionRevision: ZERO_REVISION, agentRunId: "run-1-stale" }),
      },
    );
    assert.equal(stale.status, 409);
    assert.equal(observer.receivedCommands.some((item) => item.type === "command.abort"), false);

    await assert.rejects(
      connectFakeBridge(fixture.config, "ts_001", fixture.workspace, {
        sessionId: "second-controller",
        accessMode: "controller",
        instanceEpoch: "33333333-3333-4333-8333-333333333333",
      }),
      /registration was rejected/,
    );

    await controller.close();
    controller = undefined;
    await waitForState(fixture, "idle");
    const workspaceResponse = await api(fixture, "/api/v4/workspaces");
    const workspacePayload = await workspaceResponse.json() as {
      data: Array<{ liveSessionCount: number }>;
    };
    assert.equal(workspacePayload.data[0]?.liveSessionCount, 1);
  } finally {
    await controller?.close();
    await observer?.close();
    await fixture.application.close();
  }
});

test("HTTP boundary rejects path, direct-command, and malformed-id attacks", async () => {
  const fixture = await startFixture(256);
  try {
    const escaped = await api(fixture, "/api/v4/workspaces/ts_001%2F..%2Fother/sessions/session-test/messages");
    assert.equal(escaped.status, 400);
    const unsupported = await api(fixture, "/api/v4/workspaces/ts_001/sessions/session-test/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        clientMessageId: "m-1",
        sessionRevision: ZERO_REVISION,
        message: "hello",
        command: "rm",
      }),
    });
    assert.equal(unsupported.status, 400);
    const invalidId = await sendPrompt(fixture, "bad id", "hello");
    assert.equal(invalidId.status, 400);
    const oversized = await sendPrompt(fixture, "m-2", "x".repeat(500));
    assert.equal(oversized.status, 413);
  } finally {
    await fixture.application.close();
  }
});

interface Fixture {
  application: Awaited<ReturnType<typeof createTsPhoneHttpServer>>;
  config: ServerConfig;
  baseUrl: string;
  headers: { Authorization: string };
  workspace: string;
  bridge?: FakeBridge;
}

async function startFixture(maxBodyBytes = 128 * 1024): Promise<Fixture> {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-fixture-"));
  const workspaceRoot = join(root, "workspaces");
  const workspace = join(workspaceRoot, "ts_001");
  await mkdir(workspace, { recursive: true });
  const config: ServerConfig = {
    host: "127.0.0.1",
    port: 0,
    workspaceRoot,
    stateDir: join(root, "state"),
    tspiPath: undefined,
    bridgeSocketPath: join(root, "run", "bridge.sock"),
    bridgeSecretPath: join(root, "state", "bridge.secret"),
    commandTimeoutMs: 2_000,
    shutdownTimeoutMs: 2_000,
    bridgeHeartbeatTimeoutMs: 10_000,
    bridgeMaxRecordBytes: 1024 * 1024,
    maxBodyBytes,
    eventJournalSize: 100,
    eventJournalMaxBytes: 1024 * 1024,
  };
  const application = await createTsPhoneHttpServer(config);
  const address = await application.listen();
  const token = await readBearerToken(config.stateDir);
  return {
    application,
    config,
    baseUrl: `http://127.0.0.1:${address.port}`,
    headers: { Authorization: `Bearer ${token}` },
    workspace,
  };
}

async function restartFixture(fixture: Fixture): Promise<void> {
  await fixture.application.close();
  fixture.application = await createTsPhoneHttpServer(fixture.config);
  const address = await fixture.application.listen();
  fixture.baseUrl = `http://127.0.0.1:${address.port}`;
}

async function writePersistedHistory(
  workspaceRoot: string,
  sessionId: string,
  messages: unknown[],
): Promise<string> {
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  const file = join(sessionsRoot, `${sessionId}.jsonl`);
  const records = [
    {
      type: "session",
      version: 3,
      id: sessionId,
      timestamp: new Date().toISOString(),
      cwd: workspaceRoot,
    },
    ...messages.map((message, index) => ({
      type: "message",
      id: index.toString(16).padStart(8, "0"),
      parentId: index === 0 ? null : (index - 1).toString(16).padStart(8, "0"),
      timestamp: new Date().toISOString(),
      message,
    })),
  ];
  await writeFile(file, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
  return file;
}

function api(fixture: Fixture, path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${fixture.baseUrl}${path}`, {
    ...init,
    headers: { ...fixture.headers, ...init.headers },
  });
}

async function sendPrompt(fixture: Fixture, clientMessageId: string, message: string): Promise<Response> {
  const sessionRevision = await currentRevision(fixture);
  return api(fixture, "/api/v4/workspaces/ts_001/sessions/session-test/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ clientMessageId, sessionRevision, message }),
  });
}

async function currentRevision(fixture: Fixture): Promise<string> {
  const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
  if (!response.ok) return ZERO_REVISION;
  const payload = await response.json() as { data?: Array<{ sessionRevision?: string }> };
  return payload.data?.find((session) => session.sessionRevision)?.sessionRevision || ZERO_REVISION;
}

interface SessionListItem {
  sessionId: string;
  sessionRevision: string;
  accessMode: string;
}

async function waitForSessionCount(fixture: Fixture, expectedCount: number): Promise<SessionListItem[]> {
  let sessions: SessionListItem[] = [];
  await waitFor(async () => {
    const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions");
    const payload = await response.json() as { data: SessionListItem[] };
    sessions = payload.data;
    return sessions.length;
  }, expectedCount);
  return sessions;
}

async function waitForState(fixture: Fixture, expected: string): Promise<void> {
  await waitFor(async () => {
    const response = await api(fixture, "/api/v4/workspaces");
    const payload = await response.json() as { data: Array<{ runtimeState: string }> };
    return payload.data[0]?.runtimeState;
  }, expected);
}

async function waitForMessages(fixture: Fixture, expected: string): Promise<void> {
  await waitFor(async () => {
    const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions/session-test/messages");
    return (await response.text()).includes(expected);
  }, true);
}

interface MessageSnapshotResponse {
  sessionId: string;
  sessionRevision: string;
  activeAgentRunId: string | null;
  messages: unknown[];
  lastEventId: string;
}

async function readSnapshot(fixture: Fixture): Promise<MessageSnapshotResponse> {
  const response = await api(fixture, "/api/v4/workspaces/ts_001/sessions/session-test/messages");
  assert.equal(response.status, 200);
  const payload = await response.json() as { data: MessageSnapshotResponse };
  return payload.data;
}

async function waitForSnapshot(fixture: Fixture, expectedCount: number): Promise<MessageSnapshotResponse> {
  let latest: MessageSnapshotResponse | undefined;
  await waitFor(async () => {
    latest = await readSnapshot(fixture);
    return latest.messages.length;
  }, expectedCount);
  return latest!;
}

function assistantMessage(text: string): unknown {
  return {
    role: "assistant",
    content: [{ type: "text", text }],
    timestamp: Date.now(),
  };
}

function toolResultMessage(text: string): unknown {
  return {
    role: "toolResult",
    toolCallId: "tool-1",
    toolName: "test-tool",
    content: [{ type: "text", text }],
    isError: false,
    timestamp: Date.now(),
  };
}

function messageRole(value: unknown): unknown {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>).role
    : undefined;
}

async function readSseRecord(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<string> {
  const decoder = new TextDecoder();
  let buffer = "";
  while (!buffer.includes("\n\n")) {
    const { value, done } = await reader.read();
    if (done) throw new Error("SSE stream ended before an event was received");
    buffer += decoder.decode(value, { stream: true });
  }
  return buffer.slice(0, buffer.indexOf("\n\n"));
}

async function waitFor<T>(read: () => Promise<T>, expected: T): Promise<T> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const value = await read();
      if (value === expected) return value;
    } catch {
      // The observed state is allowed to converge during this bounded test wait.
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error(`Timed out waiting for ${String(expected)}`);
}
