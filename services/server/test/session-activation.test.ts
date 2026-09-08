import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ServerConfig } from "../src/config.js";
import { HttpError } from "../src/errors.js";
import { createTsPhoneHttpServer } from "../src/http-server.js";
import { ManagementStore } from "../src/management-store.js";
import { WorkerSupervisor } from "../src/runtime/worker-supervisor.js";
import { readBearerToken } from "../src/security.js";
import { writeFakeTspi } from "./fake-tspi.js";
import { connectFakeBridge } from "./helpers.js";

async function fixture(options: Parameters<typeof writeFakeTspi>[3] = {}) {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-activation-"));
  const config: ServerConfig = {
    host: "127.0.0.1", port: 0, workspaceRoot: join(root, "workspaces"),
    stateDir: join(root, "state"), tspiPath: join(root, "TSPi"),
    bridgeSocketPath: join(root, "run", "bridge.sock"), bridgeSecretPath: join(root, "state", "bridge.secret"),
    commandTimeoutMs: 2_000, shutdownTimeoutMs: 2_000, bridgeHeartbeatTimeoutMs: 10_000,
    bridgeMaxRecordBytes: 1024 * 1024, maxBodyBytes: 128 * 1024,
    eventJournalSize: 100, eventJournalMaxBytes: 1024 * 1024,
  };
  await mkdir(config.workspaceRoot);
  await writeFakeTspi(config.tspiPath!, config.workspaceRoot, false, { bridge: true, ...options });
  const application = await createTsPhoneHttpServer(config);
  const address = await application.listen();
  const token = await readBearerToken(config.stateDir);
  return { root, config, application, hub: application.hub, address, token };
}

test("explicit activation resumes legacy Observer history without replacing it", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Existing research" });
    const directory = join(f.config.workspaceRoot, created.workspace.id, ".pi", "sessions");
    await mkdir(directory, { recursive: true });
    const path = join(directory, "historical.jsonl");
    const original = JSON.stringify({ type: "session", version: 3, id: "historical-session",
      timestamp: "2026-09-07T00:00:00.000Z", cwd: join(f.config.workspaceRoot, created.workspace.id) }) + "\n";
    await writeFile(path, original);
    const history = (await f.hub.listSessions(created.workspace.id)).find((s) => s.sessionId === "historical-session")!;
    assert.equal(history.accessMode, "observer");
    const result = await f.hub.activateSession(created.workspace.id, history.sessionId, {
      managementRevision: history.managementRevision, accessMode: "controller", requestId: "restore-history",
    });
    assert.equal(result.sessionId, history.sessionId);
    assert.equal(result.currentAccessMode, "controller");
    assert.equal(result.runtimeOwner, "host");
    assert.equal(result.canPrompt, true);
    assert.equal(await readFile(path, "utf8"), original);
  } finally { await f.application.close(); }
});

test("activation waits for a snapshot, joins duplicate requests, and does not block another workspace", async () => {
  const f = await fixture({ snapshotDelayMs: 200 });
  try {
    const created = await f.hub.createWorkspace({ name: "Slow model registry" });
    const input = { managementRevision: created.session.managementRevision, accessMode: "controller" as const, requestId: "one-start" };
    const first = f.hub.activateSession(created.workspace.id, created.session.sessionId, input);
    const duplicate = f.hub.activateSession(created.workspace.id, created.session.sessionId, input);
    const other = await f.hub.createWorkspace({ name: "Independent project" });
    assert.equal(other.workspace.id, "ts_002");
    const during = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(during.canPrompt, false);
    await assert.rejects(() => f.hub.archiveSession(created.workspace.id, created.session.sessionId,
      { managementRevision: created.session.managementRevision }),
      (error: unknown) => error instanceof HttpError && error.code === "workspace_activating");
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, created.session.sessionId,
      { ...input, accessMode: "observer" }),
      (error: unknown) => error instanceof HttpError && error.code === "activation_id_conflict");
    const [left, right] = await Promise.all([first, duplicate]);
    assert.equal(left.sessionRevision, right.sessionRevision);
    assert.equal(left.canPrompt, true);
    const starts = (await readFile(`${f.config.tspiPath}.starts`, "utf8")).trim().split("\n");
    assert.equal(starts.length, 1);
    const retry = await f.hub.activateSession(created.workspace.id, created.session.sessionId, input);
    assert.equal(retry.sessionRevision, left.sessionRevision);
  } finally { await f.application.close(); }
});

test("a preflight-acknowledged prompt without a run still prevents switching or archiving", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Pending input" });
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "controller",
    });
    const input = { sessionRevision: active.sessionRevision, clientMessageId: "pending-input", message: "One pending input" };
    await f.hub.prompt(created.workspace.id, active.sessionId, input);
    await assert.rejects(() => f.hub.prompt(created.workspace.id, active.sessionId, { ...input, message: "Different content" }),
      (error: unknown) => error instanceof HttpError && error.code === "message_id_conflict");
    const next = await f.hub.createSession(created.workspace.id, { accessMode: "controller" });
    assert.equal(next.activation?.conflict?.switchable, false);
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, next.sessionId, {
      managementRevision: next.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: active.sessionId, sessionRevision: active.sessionRevision },
    }), (error: unknown) => error instanceof HttpError && error.code === "controller_session_active");
    await assert.rejects(() => f.hub.archiveSession(created.workspace.id, active.sessionId,
      { managementRevision: active.managementRevision }),
      (error: unknown) => error instanceof HttpError && error.code === "session_active");
  } finally { await f.application.close(); }
});

test("external CLI is never stopped or silently changed to a requested mode", async () => {
  const f = await fixture();
  let bridge: Awaited<ReturnType<typeof connectFakeBridge>> | undefined;
  try {
    const created = await f.hub.createWorkspace({ name: "External owner" });
    bridge = await connectFakeBridge(f.config, created.workspace.id, join(f.config.workspaceRoot, created.workspace.id),
      { sessionId: created.session.sessionId, accessMode: "controller" });
    await new Promise((resolve) => setTimeout(resolve, 30));
    const active = (await f.hub.listSessions(created.workspace.id))[0]!;
    const next = await f.hub.createSession(created.workspace.id, { accessMode: "controller" });
    assert.equal(next.activation?.conflict?.owner, "external");
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, next.sessionId, {
      managementRevision: next.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: active.sessionId, sessionRevision: active.sessionRevision },
    }), (error: unknown) => error instanceof HttpError && error.code === "external_controller");
    assert.equal((await f.hub.listSessions(created.workspace.id)).find((s) => s.sessionId === active.sessionId)?.runtimeOwner, "external");
  } finally { await bridge?.close(); await f.application.close(); }
});

test("an unknown or late Host launch cannot enter as an external bridge", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Late registration" });
    await assert.rejects(() => connectFakeBridge(f.config, created.workspace.id,
      join(f.config.workspaceRoot, created.workspace.id), {
        sessionId: created.session.sessionId, launchId: "expired-launch", accessMode: "controller",
      }), /registration was rejected/);
    const session = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(session.canPrompt, false);
    assert.equal(session.currentAccessMode, null);
  } finally { await f.application.close(); }
});

test("model failure releases only the new Worker and preserves its saved preference", async () => {
  const f = await fixture({ promptProblem: "model_auth_missing" });
  try {
    const created = await f.hub.createWorkspace({ name: "No provider key" });
    const observer = await f.hub.createSession(created.workspace.id, { accessMode: "observer" });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, observer.sessionId, {
      managementRevision: observer.managementRevision, accessMode: "controller", requestId: "missing-key",
    }), (error: unknown) => error instanceof HttpError && error.code === "model_auth_missing");
    const after = (await f.hub.listSessions(created.workspace.id)).find((s) => s.sessionId === observer.sessionId)!;
    assert.equal(after.accessMode, "observer");
    assert.equal(after.currentAccessMode, null);
    assert.equal(after.runtimeOwner, null);
    assert.equal(after.runtimeState, "offline");
    assert.equal(after.canPrompt, false);
    assert.equal(after.managementRevision, observer.managementRevision);
  } finally { await f.application.close(); }
});

test("idle conversation and same-session mode switches require the exact source revision", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Switching" });
    const first = await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "observer",
    });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, first.sessionId, {
      managementRevision: first.managementRevision, accessMode: "controller",
    }), (error: unknown) => error instanceof HttpError && error.code === "session_switch_required");
    const promoted = await f.hub.activateSession(created.workspace.id, first.sessionId, {
      managementRevision: first.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: first.sessionId, sessionRevision: first.sessionRevision },
    });
    assert.equal(promoted.currentAccessMode, "controller");
    const next = await f.hub.createSession(created.workspace.id, { accessMode: "controller" });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, next.sessionId, {
      managementRevision: next.managementRevision, accessMode: "controller",
    }), (error: unknown) => error instanceof HttpError && error.code === "session_switch_required");
    assert.equal((await f.hub.listSessions(created.workspace.id)).find((s) => s.sessionId === first.sessionId)?.canPrompt, true);
    const switched = await f.hub.activateSession(created.workspace.id, next.sessionId, {
      managementRevision: next.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: promoted.sessionId, sessionRevision: promoted.sessionRevision },
    });
    assert.equal(switched.currentAccessMode, "controller");
    assert.equal((await f.hub.listSessions(created.workspace.id)).find((s) => s.sessionId === first.sessionId)?.runtimeState, "offline");
  } finally { await f.application.close(); }
});

test("HTTP activation accepts explicit mode and rejects malformed or unknown fields", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "API boundary" });
    const activate = (body: unknown) => fetch(`http://127.0.0.1:${f.address.port}/api/v4/workspaces/${created.workspace.id}/sessions/${created.session.sessionId}/activate`, {
      method: "POST", headers: { Authorization: `Bearer ${f.token}`, "Content-Type": "application/json" }, body: JSON.stringify(body),
    });
    assert.equal((await activate({ managementRevision: created.session.managementRevision, accessMode: "admin" })).status, 400);
    assert.equal((await activate({ managementRevision: created.session.managementRevision, command: "arbitrary" })).status, 400);
    assert.equal((await activate({ managementRevision: created.session.managementRevision, accessMode: "controller", requestId: "http-start" })).status, 200);
  } finally { await f.application.close(); }
});

test("a failed compatibility preflight leaves the same-session runtime usable", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Keep the existing assistant" });
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "observer",
    });
    await writeFakeTspi(f.config.tspiPath!, f.config.workspaceRoot, false, { guardCompatible: false });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, active.sessionId, {
      managementRevision: active.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: active.sessionId, sessionRevision: active.sessionRevision },
    }), (error: unknown) => error instanceof HttpError && error.code === "session_guard_upgrade_required");
    const after = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(after.currentAccessMode, "observer");
    assert.equal(after.runtimeState, "idle");
    assert.equal(after.canPrompt, true);
    assert.equal(after.sessionRevision, active.sessionRevision);
    assert.equal(after.managementRevision, active.managementRevision);
    assert.equal((await readFile(`${f.config.tspiPath}.starts`, "utf8")).trim().split("\n").length, 1);
  } finally { await f.application.close(); }
});

test("an uncertain source stop blocks further input and does not start the target", async (t) => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Uncertain stop" });
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "controller",
    });
    const next = await f.hub.createSession(created.workspace.id, { accessMode: "controller" });
    t.mock.method(WorkerSupervisor.prototype, "stop", async () => {
      throw new HttpError(409, "worker_cleanup_uncertain", "Process exit not confirmed");
    });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, next.sessionId, {
      managementRevision: next.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: active.sessionId, sessionRevision: active.sessionRevision },
    }), (error: unknown) => error instanceof HttpError && error.code === "worker_cleanup_uncertain");
    const sessions = await f.hub.listSessions(created.workspace.id);
    const source = sessions.find((s) => s.sessionId === active.sessionId)!;
    const target = sessions.find((s) => s.sessionId === next.sessionId)!;
    assert.equal(source.runtimeState, "recovery_required");
    assert.equal(source.canPrompt, false);
    assert.equal(target.runtimeState, "offline");
    assert.equal(target.activation?.conflict?.switchable, false);
    assert.equal((await readFile(`${f.config.tspiPath}.starts`, "utf8")).trim().split("\n").length, 1);
  } finally { t.mock.restoreAll(); await f.application.close(); }
});

test("startup exit after a confirmed switch leaves both histories offline without compensation", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Failed new runtime" });
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "controller",
    });
    const next = await f.hub.createSession(created.workspace.id, { accessMode: "observer" });
    await writeFakeTspi(f.config.tspiPath!, f.config.workspaceRoot, false, { exitBeforeBridge: true });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, next.sessionId, {
      managementRevision: next.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: active.sessionId, sessionRevision: active.sessionRevision },
    }), (error: unknown) => error instanceof HttpError && error.code === "worker_start_failed"
      && !error.message.includes("private-provider-diagnostic"));
    const sessions = await f.hub.listSessions(created.workspace.id);
    assert.equal(sessions.length, 2);
    for (const session of sessions) {
      assert.equal(session.runtimeState, "offline");
      assert.equal(session.runtimeOwner, null);
      assert.equal(session.currentAccessMode, null);
    }
    const target = sessions.find((s) => s.sessionId === next.sessionId)!;
    assert.equal(target.accessMode, "observer");
    assert.equal(target.managementRevision, next.managementRevision);
  } finally { await f.application.close(); }
});

test("launcher guard errors reach HTTP and safe logs without leaking stderr", async (t) => {
  const warnings: string[] = [];
  t.mock.method(console, "warn", (line: string) => warnings.push(line));
  for (const [code, status] of [
    ["session_writer_active", 409],
    ["session_writer_inspection_failed", 503],
    ["session_guard_invalid", 409],
  ] as const) {
    const f = await fixture({
      exitBeforeBridge: true,
      startupStderr: "private-provider-diagnostic".repeat(1000) + "\n"
        + JSON.stringify({ type: "tspi.startup_error", code }) + "\n",
    });
    try {
      const created = await f.hub.createWorkspace({ name: "Guard failure" });
      const response = await fetch(`http://127.0.0.1:${f.address.port}/api/v4/workspaces/${created.workspace.id}/sessions/${created.session.sessionId}/activate`, {
        method: "POST", headers: { Authorization: `Bearer ${f.token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ managementRevision: created.session.managementRevision, accessMode: "controller" }),
      });
      assert.equal(response.status, status);
      const body = await response.text();
      assert.equal(JSON.parse(body).error.code, code);
      assert.ok(!body.includes("private-provider-diagnostic"));
      assert.deepEqual(JSON.parse(warnings.at(-1)!), { event: "worker_start_failed", workspaceId: created.workspace.id, code });
      const after = (await f.hub.listSessions(created.workspace.id))[0]!;
      assert.equal(after.managementRevision, created.session.managementRevision);
      assert.equal(after.runtimeState, "offline");
      assert.equal(after.runtimeOwner, null);
      assert.equal(after.canPrompt, false);
    } finally { await f.application.close(); }
  }
});

test("unknown or malformed startup diagnostics remain private generic failures", async (t) => {
  const warnings: string[] = [];
  t.mock.method(console, "warn", (line: string) => warnings.push(line));
  for (const diagnostic of [
    "session_writer_inspection_failed: private-provider-diagnostic",
    JSON.stringify({ type: "tspi.startup_error", code: "private-provider-diagnostic" }),
    JSON.stringify({ type: "tspi.startup_error", code: "session_writer_inspection_failed", message: "private-provider-diagnostic" }),
    JSON.stringify({ type: "another-record", code: "session_writer_inspection_failed" }),
    "{malformed-private-provider-diagnostic}",
  ]) {
    const f = await fixture({ exitBeforeBridge: true, startupStderr: diagnostic + "\n" });
    try {
      const created = await f.hub.createWorkspace({ name: "Private launch output" });
      await assert.rejects(() => f.hub.activateSession(created.workspace.id, created.session.sessionId, {
        managementRevision: created.session.managementRevision, accessMode: "controller",
      }), (error: unknown) => error instanceof HttpError && error.code === "worker_start_failed"
        && !error.message.includes("private-provider-diagnostic"));
      assert.deepEqual(JSON.parse(warnings.at(-1)!), {
        event: "worker_start_failed", workspaceId: created.workspace.id, code: "worker_start_failed",
      });
    } finally { await f.application.close(); }
  }
});

test("activation metadata failure releases its new runtime and retains prior metadata", async (t) => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Metadata write failure" });
    const session = await f.hub.createSession(created.workspace.id, { accessMode: "observer" });
    t.mock.method(ManagementStore.prototype, "rememberSessionActivation", async () => {
      throw new Error("injected activation persistence failure");
    });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, session.sessionId, {
      managementRevision: session.managementRevision, accessMode: "controller",
    }), /injected activation persistence failure/);
    const after = (await f.hub.listSessions(created.workspace.id)).find((s) => s.sessionId === session.sessionId)!;
    assert.equal(after.accessMode, "observer");
    assert.equal(after.managementRevision, session.managementRevision);
    assert.equal(after.runtimeOwner, null);
    assert.equal(after.currentAccessMode, null);
    assert.equal(after.runtimeState, "offline");
  } finally { t.mock.restoreAll(); await f.application.close(); }
});

test("a live Observer cannot replace itself and a different Controller with one confirmation", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Two different runtimes" });
    const controller = await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "controller",
    });
    const session = await f.hub.createSession(created.workspace.id, { accessMode: "observer" });
    const observer = await f.hub.activateSession(created.workspace.id, session.sessionId, {
      managementRevision: session.managementRevision, accessMode: "observer",
    });
    assert.deepEqual(observer.activation?.modes, ["observer"]);
    assert.equal(observer.activation?.conflict?.sessionId, controller.sessionId);
    assert.equal(observer.activation?.conflict?.switchable, false);
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, observer.sessionId, {
      managementRevision: observer.managementRevision, accessMode: "controller",
      switchFrom: { sessionId: controller.sessionId, sessionRevision: controller.sessionRevision },
    }), (error: unknown) => error instanceof HttpError && error.code === "controller_session_active");
    const sessions = await f.hub.listSessions(created.workspace.id);
    assert.ok(sessions.every((s) => s.canPrompt && s.runtimeState === "idle"));
  } finally { await f.application.close(); }
});

test("Bridge admission refuses an unverified writer even with a valid shared secret", async () => {
  const f = await fixture({ writerVerified: false });
  try {
    const created = await f.hub.createWorkspace({ name: "Guard proof" });
    await assert.rejects(() => connectFakeBridge(f.config, created.workspace.id,
      join(f.config.workspaceRoot, created.workspace.id), {
        sessionId: created.session.sessionId, accessMode: "controller",
      }), /registration was rejected/);
    const session = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(session.currentAccessMode, null);
    assert.equal(session.runtimeOwner, null);
    assert.equal(session.canPrompt, false);
  } finally { await f.application.close(); }
});

test("workspace deletion can stop an owned runtime only after an idle snapshot", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({ name: "Confirmed idle runtime" });
    await f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "controller",
    });
    const preflight = await f.hub.workspaceDeletionPreflight(created.workspace.id);
    assert.equal(preflight.activeWorkers, 0);
    assert.equal(preflight.canDelete, true);
    const trashed = await f.hub.trashWorkspace(created.workspace.id, {
      managementRevision: preflight.managementRevision,
    });
    assert.equal(trashed.lifecycleState, "trashed");
    const session = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(session.runtimeState, "offline");
    assert.equal(session.runtimeOwner, null);
  } finally { await f.application.close(); }
});

test("a snapshot timeout releases the new Worker without advertising live authority", async () => {
  const f = await fixture({ snapshotDelayMs: 30_000 });
  try {
    const created = await f.hub.createWorkspace({ name: "Snapshot not ready" });
    await assert.rejects(() => f.hub.activateSession(created.workspace.id, created.session.sessionId, {
      managementRevision: created.session.managementRevision, accessMode: "controller",
    }), (error: unknown) => error instanceof HttpError && error.code === "worker_start_timeout");
    const session = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(session.runtimeState, "offline");
    assert.equal(session.runtimeOwner, null);
    assert.equal(session.currentAccessMode, null);
    assert.equal(session.canPrompt, false);
    assert.equal(session.managementRevision, created.session.managementRevision);
  } finally { await f.application.close(); }
});
