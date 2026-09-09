import assert from "node:assert/strict";
import { mkdtemp, readFile, rename, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import test from "node:test";
import { CommandQueue, commandOutcome } from "../src/runtime/command-queue.js";
import { HttpError, RuntimeError } from "../src/errors.js";

const input = (id: string) => ({clientMessageId: id, sessionRevision: "revision", message: `message ${id}`});
async function until(check: () => boolean | Promise<boolean>) {
  const end = Date.now() + 3_000;
  while (!await check()) {
    if (Date.now() > end) throw new Error("Queue did not reach expected state");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

test("queue holds each workspace until its turn settles and runs other workspaces independently", async () => {
  const queue = await CommandQueue.open(await mkdtemp(join(tmpdir(), "ts-phone-queue-")));
  const dispatched: string[] = [];
  queue.connect({ready: () => true, changed: () => {}, dispatch: async (c) => { dispatched.push(c.clientMessageId); }});
  try {
    await queue.enqueue("ws_1", "session_1", input("first"));
    await queue.enqueue("ws_1", "session_2", input("second"));
    await queue.enqueue("ws_2", "session_1", input("other"));
    await until(() => dispatched.length === 2);
    assert.deepEqual(dispatched, ["first", "other"]);
    assert.equal(queue.view("ws_1", "session_2").find((c) => c.clientMessageId === "second")?.position, 2);
    queue.settle("ws_1", "session_1", "first", {status: "completed"});
    await until(() => dispatched.length === 3);
    assert.equal(dispatched[2], "second");
    assert.equal(queue.find("ws_1", "session_1", "first")?.message, undefined);
  } finally { await queue.close(); }
});

test("queued commands can be cancelled; acknowledged dispatch cannot", async () => {
  const queue = await CommandQueue.open(await mkdtemp(join(tmpdir(), "ts-phone-queue-")));
  let ready = false;
  const dispatched: string[] = [];
  queue.connect({ready: () => ready, changed: () => {}, dispatch: async (c) => {dispatched.push(c.clientMessageId);}});
  try {
    await queue.enqueue("ws", "session", input("cancel"));
    await queue.cancel("ws", "session", "cancel");
    ready = true;
    await queue.enqueue("ws", "session", input("run"));
    await until(() => dispatched.length === 1);
    assert.deepEqual(dispatched, ["run"]);
    await assert.rejects(queue.cancel("ws", "session", "run"), {code: "command_already_started"});
  } finally { await queue.close(); }
});

test("restart preserves queued work and durable deduplication but never replays an uncertain command", async () => {
  const dir = await mkdtemp(join(tmpdir(), "ts-phone-queue-"));
  const first = await CommandQueue.open(dir);
  first.connect({ready: () => true, changed: () => {}, dispatch: async () => {}});
  await first.enqueue("ws", "session_1", input("first"), "test/model-a");
  await until(() => first.find("ws", "session_1", "first")?.status === "running");
  await first.enqueue("ws", "session_2", input("second"), "test/model-b");
  await first.close();
  const second = await CommandQueue.open(dir);
  const dispatched: string[] = [];
  second.connect({ready: () => true, changed: () => {}, dispatch: async (c) => {dispatched.push(c.clientMessageId);}});
  try {
    assert.equal(second.find("ws", "session_1", "first")?.status, "unknown");
    assert.equal((await second.enqueue("ws", "session_1", input("first"))).status, "unknown");
    await assert.rejects(second.enqueue("ws", "session_1", {...input("first"), message: "changed"}), {code: "message_id_conflict"});
    assert.equal(dispatched.length, 0);
    await second.acknowledge("ws", "session_1", "first");
    await until(() => dispatched.length === 1);
    assert.deepEqual(dispatched, ["second"]);
    assert.equal(second.find("ws", "session_2", "second")?.model, "test/model-b");
    assert.equal((await stat(join(dir, "commands.json"))).mode & 0o077, 0);
    const stored = JSON.parse(await readFile(join(dir, "commands.json"), "utf8"));
    assert.equal(stored.commands[0].message, undefined);
  } finally { await second.close(); }
});

test("a fast settled event arriving before its RPC receipt does not strand the next request", async () => {
  const queue = await CommandQueue.open(await mkdtemp(join(tmpdir(), "ts-phone-queue-")));
  const dispatched: string[] = [];
  queue.connect({ready: () => true, changed: () => {}, dispatch: async (c) => {
    dispatched.push(c.clientMessageId);
    queue.settle(c.workspaceId, c.sessionId, c.clientMessageId, {status: "completed"});
    await new Promise((resolve) => setTimeout(resolve, 20));
  }});
  try {
    await queue.enqueue("ws", "session", input("first"));
    await queue.enqueue("ws", "session", input("second"));
    await until(() => queue.find("ws", "session", "second")?.status === "completed");
    assert.deepEqual(dispatched, ["first", "second"]);
  } finally { await queue.close(); }
});

test("a definite rejection releases the lane; ambiguous dispatch blocks it without replay", async () => {
  const queue = await CommandQueue.open(await mkdtemp(join(tmpdir(), "ts-phone-queue-")));
  const dispatched: string[] = [];
  queue.connect({ready: () => true, changed: () => {}, dispatch: async (c) => {
    dispatched.push(c.clientMessageId);
    if (c.clientMessageId === "reject") throw new HttpError(409, "model_auth_missing", "No model authentication");
    if (c.clientMessageId === "uncertain") throw new RuntimeError("command_ambiguous", "Lost receipt");
  }});
  try {
    await queue.enqueue("ws", "session", input("reject"));
    await queue.enqueue("ws", "session", input("uncertain"));
    await queue.enqueue("ws", "session", input("later"));
    await until(() => queue.find("ws", "session", "uncertain")?.status === "unknown");
    assert.equal(queue.find("ws", "session", "reject")?.problem, "model_auth_missing");
    assert.equal(queue.find("ws", "session", "reject")?.status, "failed");
    assert.deepEqual(dispatched, ["reject", "uncertain"]);
    await queue.acknowledge("ws", "session", "uncertain");
    await until(() => dispatched.length === 3);
    assert.deepEqual(dispatched, ["reject", "uncertain", "later"]);
  } finally { await queue.close(); }
});

test("disconnect keeps the interrupted turn unknown even after a late settled notification", async () => {
  const queue = await CommandQueue.open(await mkdtemp(join(tmpdir(), "ts-phone-queue-")));
  queue.connect({ready: () => true, changed: () => {}, dispatch: async () => {}});
  try {
    await queue.enqueue("ws", "session", input("once"));
    await until(() => queue.find("ws", "session", "once")?.status === "running");
    queue.disconnected("ws", "session");
    await until(() => queue.hasUnknown("ws"));
    queue.settle("ws", "session", "once", {status: "completed"});
    assert.equal(queue.find("ws", "session", "once")?.status, "unknown");
    await assert.rejects(queue.cancel("ws", "session", "once"), {code: "command_already_started"});
  } finally { await queue.close(); }
});

test("settlement binds one request, records failure and cancellation, and rejects false success", async () => {
  const dir = await mkdtemp(join(tmpdir(), "ts-phone-queue-"));
  const queue = await CommandQueue.open(dir);
  queue.connect({ready: () => true, changed: () => {}, dispatch: async () => {}});
  try {
    await queue.enqueue("ws", "session", input("first"));
    await queue.enqueue("ws", "session", input("second"));
    await until(() => queue.find("ws", "session", "first")?.status === "running");
    queue.settle("ws", "session", "first", commandOutcome({outcome: {status: "failed", problem: "provider_unavailable"}}));
    await until(() => queue.find("ws", "session", "second")?.status === "running");
    queue.settle("ws", "session", "first", {status: "completed"});
    assert.equal(queue.find("ws", "session", "first")?.status, "failed");
    assert.equal(queue.find("ws", "session", "first")?.problem, "provider_unavailable");
    assert.equal(queue.find("ws", "session", "second")?.status, "running");
    queue.settle("ws", "session", "second", {status: "cancelled"});
    await until(() => !queue.hasPending("ws"));
    assert.equal(queue.find("ws", "session", "second")?.status, "cancelled");
    assert.deepEqual(commandOutcome({}), {status: "failed", problem: "generation_unconfirmed"});
    assert.deepEqual(commandOutcome({outcome: {status: "failed", problem: "private-api-key"}}),
      {status: "failed", problem: "generation_unconfirmed"});
  } finally { await queue.close(); }
  const reopened = await CommandQueue.open(dir);
  try { assert.equal(reopened.find("ws", "session", "first")?.problem, "provider_unavailable"); }
  finally { await reopened.close(); }
});

test("parallel admissions deduplicate one identity and preserve one workspace lane", async () => {
  const queue = await CommandQueue.open(await mkdtemp(join(tmpdir(), "ts-phone-queue-")));
  const dispatched: string[] = [];
  queue.connect({ready: () => true, changed: () => {}, dispatch: async (c) => {dispatched.push(c.clientMessageId);}});
  try {
    await Promise.all(Array.from({length: 12}, () => queue.enqueue("ws", "session", input("same"))));
    await until(() => dispatched.length === 1);
    assert.equal(queue.pendingCount("ws"), 1);
    assert.deepEqual(dispatched, ["same"]);
  } finally { await queue.close(); }
});

test("storage failure suspends dispatch and never acknowledges a non-durable admission", async () => {
  const dir = await mkdtemp(join(tmpdir(), "ts-phone-queue-"));
  const queue = await CommandQueue.open(dir);
  const dispatched: string[] = [];
  queue.connect({ready: () => true, changed: () => {}, dispatch: async (c) => {dispatched.push(c.clientMessageId);}});
  await rename(dir, `${dir}-unavailable`);
  try {
    await assert.rejects(queue.enqueue("ws", "session", input("no-write")), {code: "queue_storage_unavailable"});
    assert.equal(queue.faulted, true);
    assert.equal(queue.find("ws", "session", "no-write"), undefined);
    assert.deepEqual(dispatched, []);
  } finally { await queue.close(); }
});

test("command store rejects unknown fields, wrong types, digest drift, and unsafe permissions", async () => {
  const dir = await mkdtemp(join(tmpdir(), "ts-phone-queue-"));
  const queue = await CommandQueue.open(dir);
  await queue.enqueue("ws", "session", input("stored"));
  await queue.close();
  const path = join(dir, "commands.json");
  const valid = JSON.parse(await readFile(path, "utf8"));
  for (const change of [ {extra: true}, {createdAt: 1}, {message: "tampered"}, {digest: []} ]) {
    await writeFile(path, JSON.stringify({...valid, commands: [{...valid.commands[0], ...change}]}), {mode: 0o600});
    await assert.rejects(CommandQueue.open(dir), /Invalid Host command/);
  }
  const {chmod} = await import("node:fs/promises");
  await writeFile(path, JSON.stringify(valid));
  await chmod(path, 0o644);
  await assert.rejects(CommandQueue.open(dir), /Unsafe Host command store/);
});

test("permanent deletion removes only scoped terminal receipts and compensates a failed deletion", async () => {
  const dir = await mkdtemp(join(tmpdir(), "ts-phone-queue-"));
  const queue = await CommandQueue.open(dir);
  try {
    await queue.enqueue("ws", "first", input("purge"));
    await queue.enqueue("ws", "second", input("keep"));
    await queue.enqueue("other", "first", input("unrelated"));
    await assert.rejects(queue.withPurgedReceipts("ws", "first", async () => {
      assert.fail("Deletion must not start while a request is pending");
    }), {code: "queue_requests_active"});
    await queue.cancel("ws", "first", "purge");
    await assert.rejects(queue.withPurgedReceipts("ws", "first", async () => {
      assert.equal(queue.find("ws", "first", "purge"), undefined);
      throw new Error("Deletion failed");
    }), /Deletion failed/);
    assert.equal((await queue.enqueue("ws", "first", input("purge"))).status, "cancelled");
    await queue.withPurgedReceipts("ws", "first", async () => {});
    assert.equal(queue.find("ws", "first", "purge"), undefined);
    assert.equal(queue.find("ws", "second", "keep")?.status, "queued");
    await queue.cancel("ws", "second", "keep");
    await queue.withPurgedReceipts("ws", undefined, async () => {});
    const stored = JSON.parse(await readFile(join(dir, "commands.json"), "utf8"));
    assert.deepEqual(stored.commands.map((c: {workspaceId: string}) => c.workspaceId), ["other"]);
    assert.equal(queue.find("other", "first", "unrelated")?.status, "queued");
  } finally { await queue.close(); }
});
