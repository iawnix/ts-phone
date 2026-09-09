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

async function waitFor(check: () => Promise<boolean>) {
  const end = Date.now() + 8_000;
  while (!await check()) {
    if (Date.now() > end) throw new Error("Host did not reach expected queue state");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

test("queued sends start inactive conversations and transfer execution only after the previous turn settles", async () => {
  const f = await fixture({modelControl: true, turnDelayMs: 150});
  try {
    const created = await f.hub.createWorkspace({name: "Queued research"});
    const id = created.workspace.id;
    const a = created.session;
    const b = await f.hub.createSession(id, {accessMode: "controller", name: "Second question"});
    assert.ok(a.capabilities.includes("command.queue"));
    await f.hub.getMessages(id, a.sessionId, {limit: 20});
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), {code: "ENOENT"});
    const send = (s: typeof a, clientMessageId: string) => f.hub.enqueue(id, s.sessionId,
      {sessionRevision: s.sessionRevision, clientMessageId, message: clientMessageId, clientKind: "phone"});
    assert.equal((await send(a, "one")).status, "queued");
    assert.equal((await send(b, "two")).status, "queued");
    await assert.rejects(f.hub.archiveWorkspace(id, {managementRevision: created.workspace.managementRevision}), {code: "queue_requests_active"});
    await waitFor(async () => (await f.hub.promptReceipt(id, b.sessionId, "two", b.sessionRevision)).status === "completed");
    const prompts = (await readFile(`${f.config.tspiPath}.prompts`, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
    const settled = (await readFile(`${f.config.tspiPath}.settled`, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(prompts.map((p) => p.message), ["one", "two"]);
    assert.deepEqual(prompts.map((p) => p.sessionId), [a.sessionId, b.sessionId]);
    assert.ok(prompts[1].at >= settled[0].at);
    assert.ok(prompts.every((p) => p.followUp === undefined));
    assert.equal((await send(a, "one")).status, "completed");
    assert.equal(f.application.hub.commandQueue?.hasPending(id), false);
  } finally { await f.application.close(); }
});

test("next-turn model preference retargets waiting sends while preserving the running send", async () => {
  const f = await fixture({modelControl: true, turnDelayMs: 4000});
  try {
    const created = await f.hub.createWorkspace({name: "Next-turn models"});
    const id = created.workspace.id;
    const s = created.session;
    await f.hub.setModel(id, s.sessionId, {sessionRevision: s.sessionRevision, provider: "test", modelId: "second", nextTurn: true});
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), {code: "ENOENT"});
    await f.hub.enqueue(id, s.sessionId, {sessionRevision: s.sessionRevision, clientMessageId: "first-model", message: "first"});
    await waitFor(async () => (await f.hub.listSessions(id))[0]?.runtimeState === "running");
    const running = (await f.hub.listSessions(id))[0]!;
    await f.hub.enqueue(id, s.sessionId, {sessionRevision: running.sessionRevision, clientMessageId: "second-model", message: "second"});
    const selected = await f.hub.setModel(id, s.sessionId, {sessionRevision: running.sessionRevision, provider: "test", modelId: "fake-model", nextTurn: true});
    assert.equal(selected.nextModel, "test/fake-model");
    assert.equal(selected.model, "test/second");
    assert.equal(f.hub.commandQueue?.find(id, s.sessionId, "second-model")?.model, "test/fake-model");
    await waitFor(async () => (await f.hub.promptReceipt(id, s.sessionId, "second-model", running.sessionRevision)).status === "completed");
    const prompts = (await readFile(`${f.config.tspiPath}.prompts`, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(prompts.map((p) => p.model), ["second", "fake-model"]);
  } finally { await f.application.close(); }
});

test("Pi retry starts keep the queue lane until final success, failure or cancellation", async () => {
  for (const outcome of ["completed", "failed", "cancelled"] as const) {
    const f = await fixture({modelControl: true, turnDelayMs: 240, retryOutcome: outcome});
    try {
      const {workspace, session} = await f.hub.createWorkspace({name: "Retry lifecycle"});
      const send = (id: string) => f.hub.enqueue(workspace.id, session.sessionId,
        {sessionRevision: session.sessionRevision, clientMessageId: id, message: id});
      await send("retry");
      await send("next");
      const journal = await f.hub.journal(workspace.id, session.sessionId);
      await waitFor(async () => journal.since(undefined).filter((e) => e.type === "agent_start").length >= 2);
      assert.equal(f.hub.commandQueue?.find(workspace.id, session.sessionId, "next")?.status, "queued");
      assert.equal(f.hub.commandQueue?.hasUnknown(workspace.id), false);
      await waitFor(async () => f.hub.commandQueue?.find(workspace.id, session.sessionId, "next")?.status === "completed");
      const first = f.hub.commandQueue?.find(workspace.id, session.sessionId, "retry");
      assert.equal(first?.status, outcome);
      assert.equal(first?.problem, outcome === "failed" ? "provider_unavailable" : undefined);
      const starts = journal.since(undefined).filter((e) => e.type === "agent_start").map((e) => e.payload as any);
      assert.equal(starts[0].agentRunId, starts[1].agentRunId);
      assert.notEqual(starts[1].agentRunId, starts[2].agentRunId);
      assert.equal((await f.hub.listSessions(workspace.id))[0]?.queueProblem, undefined);
      const prompts = (await readFile(`${f.config.tspiPath}.prompts`, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      const settlements = (await readFile(`${f.config.tspiPath}.settled`, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      assert.deepEqual(prompts.map((p) => p.message), ["retry", "next"]);
      assert.ok(prompts[1].at >= settlements[0].at);
    } finally { await f.application.close(); }
  }
});

test("HTTP queue validates authentication, identity, cancellation, and explicit recovery confirmation", async () => {
  const f = await fixture({modelControl: true, turnDelayMs: 1200});
  const headers = {authorization: `Bearer ${f.token}`, "content-type": "application/json"};
  try {
    const created = await f.hub.createWorkspace({name: "HTTP queue"});
    const id = created.workspace.id;
    const first = created.session;
    const waiting = await f.hub.createSession(id, {accessMode: "controller"});
    const base = `http://127.0.0.1:${f.address.port}/api/v4/workspaces/${id}/sessions`;
    const post = (path: string, body: unknown, auth = true) => fetch(`${base}/${path}`, {
      method: "POST", headers: auth ? headers : {"content-type": "application/json"}, body: JSON.stringify(body),
    });
    const data = {sessionRevision: first.sessionRevision, clientMessageId: "http-1", message: "first"};
    assert.equal((await post(`${first.sessionId}/commands`, data, false)).status, 401);
    assert.equal((await post(`${first.sessionId}/commands`, {...data, unexpected: true})).status, 400);
    assert.equal((await post(`${first.sessionId}/commands`, data)).status, 202);
    await waitFor(async () => (await f.hub.listSessions(id)).find((s) => s.sessionId === first.sessionId)?.runtimeState === "running");
    assert.equal((await post(`${waiting.sessionId}/commands`, {...data, sessionRevision: waiting.sessionRevision, clientMessageId: "http-2"})).status, 202);
    assert.equal((await post(`${first.sessionId}/commands`, data)).status, 202);
    assert.equal((await post(`${first.sessionId}/commands`, {...data, message: "different"})).status, 409);
    const preflight = await f.hub.workspaceDeletionPreflight(id);
    assert.equal(preflight.canDelete, false);
    assert.equal(preflight.pendingCommands, 2);
    assert.equal((await post(`${waiting.sessionId}/commands/http-2/cancel`, {}, false)).status, 401);
    assert.equal((await post(`${first.sessionId}/commands/http-2/cancel`, {})).status, 404);
    assert.equal((await post(`${waiting.sessionId}/commands/http-2/cancel`, {})).status, 200);
    assert.equal((await post(`${first.sessionId}/commands/http-1/cancel`, {})).status, 409);
    assert.equal((await post(`${first.sessionId}/commands/http-1/acknowledge`, {})).status, 400);
    assert.equal((await post(`${first.sessionId}/commands/http-1/acknowledge`, {confirmation: "wrong"})).status, 400);
    assert.equal((await post(`${first.sessionId}/commands/http-1/acknowledge`, {confirmation: "http-1"})).status, 409);
    const response = await fetch(`${base}/${waiting.sessionId}/commands/http-2?sessionRevision=${waiting.sessionRevision}`, {headers});
    const body = await response.json() as any;
    assert.equal(body.data.durable, true);
    assert.equal(body.data.status, "cancelled");
    assert.equal(body.data.message, undefined);
    assert.equal(body.data.preview, undefined);
  } finally { await f.application.close(); }
});

test("queue waits for an external Controller without stopping it and blocks inactive-project deletion", async () => {
  const f = await fixture({modelControl: true, turnDelayMs: 40});
  let bridge: Awaited<ReturnType<typeof connectFakeBridge>> | undefined;
  try {
    const created = await f.hub.createWorkspace({name: "External queue owner"});
    const id = created.workspace.id;
    bridge = await connectFakeBridge(f.config, id, join(f.config.workspaceRoot, id),
      {sessionId: created.session.sessionId, accessMode: "controller"});
    const next = await f.hub.createSession(id, {accessMode: "controller"});
    await f.hub.enqueue(id, next.sessionId, {sessionRevision: next.sessionRevision, message: "after external exit", clientMessageId: "after-cli"});
    assert.equal((await f.hub.listSessions(id)).find((s) => s.sessionId === next.sessionId)?.queueProblem, "external_controller");
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), {code: "ENOENT"});
    await assert.rejects(f.hub.archiveSession(id, next.sessionId, {managementRevision: next.managementRevision}), {code: "queue_requests_active"});
    await bridge.close();
    bridge = undefined;
    await waitFor(async () => (await f.hub.promptReceipt(id, next.sessionId, "after-cli", next.sessionRevision)).status === "completed");
    const lines = (await readFile(`${f.config.tspiPath}.starts`, "utf8")).trim().split("\n");
    assert.equal(lines.length, 1);
    assert.equal(JSON.parse(lines[0]!).sessionId, next.sessionId);
  } finally { await bridge?.close(); await f.application.close(); }
});

test("restart exposes an uncertain execution and acknowledgement never replays it", async () => {
  const f = await fixture({modelControl: true, turnDelayMs: 5000});
  const created = await f.hub.createWorkspace({name: "Restart queue"});
  const id = created.workspace.id;
  const s = created.session;
  await f.hub.enqueue(id, s.sessionId, {sessionRevision: s.sessionRevision, clientMessageId: "interrupted", message: "only once"});
  await waitFor(async () => (await f.hub.listSessions(id))[0]?.runtimeState === "running");
  await f.application.close();
  const restarted = await createTsPhoneHttpServer(f.config);
  try {
    await restarted.listen();
    assert.equal((await restarted.hub.promptReceipt(id, s.sessionId, "interrupted", s.sessionRevision)).status, "unknown");
    assert.equal((await restarted.hub.listSessions(id))[0]?.queueProblem, "queue_recovery_required");
    const acknowledged = await restarted.hub.acknowledgeCommand(id, s.sessionId, "interrupted");
    assert.equal(acknowledged.status, "acknowledged");
    assert.equal((await restarted.hub.listSessions(id))[0]?.queueProblem, undefined);
    assert.equal((await readFile(`${f.config.tspiPath}.prompts`, "utf8")).trim().split("\n").length, 1);
  } finally { await restarted.close(); }
});

test("terminal and Phone attach to one Worker and reconcile exact prompt receipts", async () => {
  const f = await fixture();
  const base = `http://127.0.0.1:${f.address.port}/api/v4`;
  const headers = { Authorization: `Bearer ${f.token}`, "Content-Type": "application/json" };
  const post = (path: string, body: unknown) => fetch(`${base}${path}`, { method: "POST", headers, body: JSON.stringify(body) });
  try {
    const created = await f.hub.createWorkspace({ name: "Shared clients", workspaceId: "ts_terminal" });
    const path = `/workspaces/${created.workspace.id}/sessions/${created.session.sessionId}`;
    assert.equal((await fetch(`${base}${path}/messages?limit=80`, { headers })).status, 200);
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), { code: "ENOENT" });
    const results = await Promise.all([1, 2].map((id) => post(`${path}/activate`, {
      managementRevision: created.session.managementRevision, requestId: `terminal-${id}`, accessMode: "controller",
    })));
    assert.ok(results.some((response) => response.status === 200));
    assert.ok(results.every((response) => response.status === 200 || response.status === 409));
    const active = (await f.hub.listSessions(created.workspace.id))[0]!;
    for (const clientKind of ["terminal", "phone"] as const) {
      const body = { message: `From ${clientKind}`, clientKind, clientMessageId: `${clientKind}-1`, sessionRevision: active.sessionRevision };
      assert.equal((await post(`${path}/messages`, body)).status, 202);
      assert.equal((await post(`${path}/messages`, body)).status, 202);
      const receiptUrl = `${base}${path}/commands/${body.clientMessageId}?sessionRevision=${active.sessionRevision}`;
      assert.equal((await fetch(receiptUrl)).status, 401);
      const receipt = await (await fetch(receiptUrl, { headers })).json() as any;
      assert.equal(receipt.data.status, "accepted");
      assert.ok(!JSON.stringify(receipt).includes(body.message));
      const changed = await post(`${path}/messages`, { ...body, message: "different prompt" });
      assert.equal(changed.status, 409);
    }
    const journal = await f.hub.journal(created.workspace.id, active.sessionId);
    const inputs = journal.since(undefined).filter((event) => event.type === "input") as any[];
    assert.equal(inputs.length, 2);
    assert.deepEqual(inputs.map((event) => event.payload.origin), ["terminal", "phone"]);
    assert.equal((await f.hub.promptReceipt(created.workspace.id, active.sessionId, "terminal-1", "old-generation")).status, "unknown");
    const starts = (await readFile(`${f.config.tspiPath}.starts`, "utf8")).trim().split("\n");
    assert.equal(starts.length, 1);
    assert.equal((await post(`${path}/messages`, {message: "invalid", clientMessageId: "bad", sessionRevision: active.sessionRevision, clientKind: "administrator"})).status, 400);
  } finally { await f.application.close(); }
});

test("named project creation stays within configured root and never overwrites identities", async () => {
  const f = await fixture();
  const url = `http://127.0.0.1:${f.address.port}/api/v4/workspaces`;
  const headers = { Authorization: `Bearer ${f.token}`, "Content-Type": "application/json" };
  try {
    for (const workspaceId of ["../escape", "/tmp/escape", ".", "a/b"]) {
      assert.equal((await fetch(url, {method: "POST", headers, body: JSON.stringify({name: "project", workspaceId})})).status, 400);
    }
    await f.hub.createWorkspace({ name: "project", workspaceId: "ts_named" });
    await assert.rejects(f.hub.createWorkspace({ name: "replacement", workspaceId: "ts_named" }), {code: "workspace_exists"});
    assert.equal((await f.hub.listWorkspaces())[0]!.name, "project");
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), { code: "ENOENT" });
  } finally { await f.application.close(); }
});

test("model catalog needs authentication and never creates or starts a conversation", async () => {
  const f = await fixture();
  try {
    const url = `http://127.0.0.1:${f.address.port}/api/v4/models`;
    assert.equal((await fetch(url)).status, 401);
    const response = await fetch(url, { headers: { authorization: `Bearer ${f.token}` } });
    assert.equal(response.status, 200);
    const body = await response.json() as any;
    assert.equal(body.data[0].id, "fake-model");
    assert.deepEqual(await f.hub.listWorkspaces(), []);
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), { code: "ENOENT" });
  } finally { await f.application.close(); }
});

test("model selection is exact, persisted, and excludes prompt and lifecycle races", async () => {
  const f = await fixture({ modelControl: true });
  try {
    const created = await f.hub.createWorkspace({ name: "Model controls" });
    const id = created.workspace.id;
    const active = await f.hub.activateSession(id, created.session.sessionId, {
      managementRevision: created.session.managementRevision,
    });
    assert.ok(active.capabilities.includes("command.model"));
    const input = { sessionRevision: active.sessionRevision, provider: "test", modelId: "second" };
    await assert.rejects(f.hub.setModel(id, active.sessionId, {...input, sessionRevision: "old"}), {code: "session_resync_required"});
    const switching = f.hub.setModel(id, active.sessionId, input);
    await new Promise((resolve) => setTimeout(resolve, 25));
    await assert.rejects(f.hub.prompt(id, active.sessionId, {sessionRevision: active.sessionRevision,
      clientMessageId: "during-switch", message: "not sent"}), {code: "session_not_ready"});
    await assert.rejects(f.hub.setModel(id, active.sessionId, input), {code: "session_not_ready"});
    const selected = await switching;
    assert.equal(selected.model, "test/second");
    assert.equal(selected.runtime?.model.id, "second");
    const store = await ManagementStore.open(f.config.stateDir);
    assert.equal(store.session(id, active.sessionId)?.model, "test/second");
    await assert.rejects(f.hub.setModel(id, active.sessionId, {...input, modelId: "rejected"}), {code: "model_unavailable"});
    assert.equal((await f.hub.listSessions(id))[0]?.model, "test/second");
    await f.hub.prompt(id, active.sessionId, {sessionRevision: active.sessionRevision,
      clientMessageId: "pending", message: "queued"});
    await assert.rejects(f.hub.setModel(id, active.sessionId, input), {code: "session_not_ready"});
  } finally { await f.application.close(); }
});

test("offline model preferences never activate a worker and only accept catalog models", async () => {
  const f = await fixture({modelControl: true});
  try {
    const created = await f.hub.createWorkspace({name: "Model preference"});
    const id = created.workspace.id;
    assert.ok(created.session.capabilities.includes("session.model_preference"));
    const input = {sessionRevision: created.session.sessionRevision, provider: "test", modelId: "fake-model"};
    await assert.rejects(f.hub.setModel(id, created.session.sessionId, {...input, modelId: "missing"}), {code: "model_unavailable"});
    const selected = await f.hub.setModel(id, created.session.sessionId, input);
    assert.equal(selected.model, "test/fake-model");
    assert.equal(selected.runtimeState, "offline");
    assert.equal(selected.currentAccessMode, null);
    assert.equal(selected.canPrompt, false);
    const journal = await f.hub.journal(id, selected.sessionId);
    const state = journal.since(undefined).filter((event) => event.type === "session_state").at(-1)!;
    assert.equal(state.payload?.model, "test/fake-model");
    assert.ok((state.payload?.capabilities as string[]).includes("session.model_preference"));
    await assert.rejects(readFile(`${f.config.tspiPath}.starts`), {code: "ENOENT"});
    const store = await ManagementStore.open(f.config.stateDir);
    assert.equal(store.session(id, selected.sessionId)?.model, "test/fake-model");
    await assert.rejects(f.hub.setModel(id, selected.sessionId, {...input, sessionRevision: "old"}), {code: "session_resync_required"});
    await f.hub.archiveSession(id, selected.sessionId, {managementRevision: selected.managementRevision});
    await assert.rejects(f.hub.setModel(id, selected.sessionId, input), {code: "session_not_ready"});
  } finally { await f.application.close(); }
});

test("idle Observer model changes preserve Observer authority", async () => {
  const f = await fixture({modelControl: true});
  try {
    const created = await f.hub.createWorkspace({name: "Read-only model"});
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId,
      {managementRevision: created.session.managementRevision, accessMode: "observer"});
    assert.ok(active.capabilities.includes("command.model"));
    const selected = await f.hub.setModel(created.workspace.id, active.sessionId,
      {sessionRevision: active.sessionRevision, provider: "test", modelId: "second"});
    assert.equal(selected.currentAccessMode, "observer");
    assert.equal(selected.accessMode, "observer");
    assert.equal(selected.model, "test/second");
  } finally { await f.application.close(); }
});

test("model HTTP input is exact and unmanaged model control stays unavailable", async () => {
  const f = await fixture();
  try {
    const created = await f.hub.createWorkspace({name: "Model capability"});
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId,
      {managementRevision: created.session.managementRevision});
    assert.ok(!active.capabilities.includes("command.model"));
    const url = `http://127.0.0.1:${f.address.port}/api/v4/workspaces/${created.workspace.id}/sessions/${active.sessionId}/model`;
    const input = {sessionRevision: active.sessionRevision, provider: "test", modelId: "second"};
    assert.equal((await fetch(url, {method: "POST", body: JSON.stringify(input)})).status, 401);
    const headers = {Authorization: `Bearer ${f.token}`, "Content-Type": "application/json"};
    assert.equal((await fetch(url, {method: "POST", headers, body: JSON.stringify({...input, model: "extra"})})).status, 400);
    const rejected = await fetch(url, {method: "POST", headers, body: JSON.stringify(input)});
    assert.equal(rejected.status, 409);
    assert.equal((await rejected.json() as any).error.code, "model_control_unavailable");
  } finally { await f.application.close(); }
});

test("a confirmed model with failed persistence enters recovery, not ready", async (t) => {
  const f = await fixture({modelControl: true});
  try {
    const created = await f.hub.createWorkspace({name: "Model persistence"});
    const active = await f.hub.activateSession(created.workspace.id, created.session.sessionId,
      {managementRevision: created.session.managementRevision});
    t.mock.method(ManagementStore.prototype, "rememberSessionModel", async () => { throw new Error("private-storage-error"); });
    await assert.rejects(f.hub.setModel(created.workspace.id, active.sessionId,
      {sessionRevision: active.sessionRevision, provider: "test", modelId: "second"}),
      {code: "model_change_unconfirmed"});
    const after = (await f.hub.listSessions(created.workspace.id))[0]!;
    assert.equal(after.runtimeState, "recovery_required");
    assert.equal(after.canPrompt, false);
  } finally { t.mock.restoreAll(); await f.application.close(); }
});

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
    assert.ok(!history.capabilities.includes("session.model_preference"));
    await assert.rejects(f.hub.setModel(created.workspace.id, history.sessionId,
      {sessionRevision: history.sessionRevision, provider: "test", modelId: "fake-model"}),
      {code: "session_not_ready"});
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
    ["model_unavailable", 409],
    ["model_check_failed", 409],
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
