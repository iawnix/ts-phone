import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, truncate, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { HttpError } from "../src/errors.js";
import { WorkspaceRegistry } from "../src/workspace-registry.js";

test("registry lists only safe TSPi workspace directories", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-registry-"));
  await mkdir(join(root, "ts_001"));
  await mkdir(join(root, "bad name"));
  await symlink(join(root, "ts_001"), join(root, "ts_link"));
  const registry = new WorkspaceRegistry(root);

  assert.deepEqual((await registry.list()).map((workspace) => workspace.name), ["ts_001"]);
  assert.equal((await registry.get("ts_001")).root, join(root, "ts_001"));
  await assert.rejects(() => registry.get("../outside"), HttpError);
  await assert.rejects(() => registry.get("ts_link"), HttpError);
});

test("registry indexes persisted Pi sessions from structured headers", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-sessions-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  await writeFile(join(sessionsRoot, "valid.jsonl"), `${JSON.stringify({
    type: "session",
    version: 3,
    id: "session-valid",
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  })}\n`);
  await writeFile(join(sessionsRoot, "other-workspace.jsonl"), `${JSON.stringify({
    type: "session",
    version: 3,
    id: "session-other",
    timestamp: new Date().toISOString(),
    cwd: join(root, "other"),
  })}\n`);
  const registry = new WorkspaceRegistry(root);
  const workspace = await registry.get("ts_001");

  const index = await registry.listPersistedSessionIds(workspace);
  assert.equal(index.complete, true);
  assert.deepEqual([...index.ids], ["session-valid"]);
});

test("registry makes session reconciliation fail open on malformed history", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-sessions-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  await writeFile(join(sessionsRoot, "malformed.jsonl"), "not-json\n");
  const registry = new WorkspaceRegistry(root);

  const index = await registry.listPersistedSessionIds(await registry.get("ts_001"));
  assert.equal(index.complete, false);
  assert.deepEqual([...index.ids], []);
});

test("registry reads bounded projected messages without exposing Pi internals", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-history-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  const sessionFile = join(sessionsRoot, "history.jsonl");
  const records: unknown[] = [{
    type: "session",
    version: 3,
    id: "session-history",
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  }];
  for (let index = 0; index < 510; index += 1) {
    records.push({
      type: "message",
      id: index.toString(16).padStart(8, "0"),
      parentId: index === 0 ? null : (index - 1).toString(16).padStart(8, "0"),
      message: {
        role: "assistant",
        provider: "private-provider",
        usage: { private: true },
        content: [
          { type: "thinking", thinking: "private-reasoning" },
          { type: "text", text: `history-${index}` },
        ],
        timestamp: index,
      },
    });
  }
  await writeFile(sessionFile, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
  const registry = new WorkspaceRegistry(root);
  const workspace = await registry.get("ts_001");
  const index = await registry.listPersistedSessionIds(workspace);
  const session = index.sessions.get("session-history");
  assert.ok(session);

  const page = await registry.readPersistedSessionMessages(workspace, session);
  assert.equal(page.messages.length, 500);
  assert.equal(page.messageIds?.[0], "0000000a");
  assert.equal(page.hasMore, true);
  assert.equal(page.nextBefore, "0000000a");
  assert.match(JSON.stringify(page.messages[0]), /history-10/);
  assert.match(JSON.stringify(page.messages.at(-1)), /history-509/);
  assert.doesNotMatch(JSON.stringify(page.messages), /private-provider|private-reasoning|usage/);

  const earlier = await registry.readPersistedSessionMessages(workspace, session, {
    before: page.nextBefore,
    limit: 7,
  });
  assert.deepEqual(earlier.messageIds, [
    "00000003",
    "00000004",
    "00000005",
    "00000006",
    "00000007",
    "00000008",
    "00000009",
  ]);
  assert.equal(earlier.hasMore, true);
  assert.equal(earlier.nextBefore, "00000003");

  const first = await registry.readPersistedSessionMessages(workspace, session, {
    before: earlier.nextBefore,
    limit: 7,
  });
  assert.deepEqual(first.messageIds, ["00000000", "00000001", "00000002"]);
  assert.equal(first.hasMore, false);
  assert.equal(first.nextBefore, undefined);

  await assert.rejects(
    () => registry.readPersistedSessionMessages(workspace, session, {
      before: "ffffffff",
      limit: 7,
    }),
    (error: unknown) => error instanceof HttpError && error.code === "session_history_cursor_invalid",
  );
});

test("registry returns only the active Pi session branch", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-branch-history-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  const records = [{
    type: "session",
    version: 3,
    id: "session-branch",
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  }, {
    type: "message",
    id: "00000001",
    parentId: null,
    message: { role: "user", content: "root", timestamp: 1 },
  }, {
    type: "message",
    id: "00000002",
    parentId: "00000001",
    message: { role: "assistant", content: [{ type: "text", text: "abandoned" }], timestamp: 2 },
  }, {
    type: "message",
    id: "00000003",
    parentId: "00000002",
    message: { role: "user", content: "abandoned-tail", timestamp: 3 },
  }, {
    type: "message",
    id: "00000004",
    parentId: "00000001",
    message: { role: "assistant", content: [{ type: "text", text: "active" }], timestamp: 4 },
  }, {
    type: "session_info",
    id: "00000005",
    parentId: "00000004",
    name: "active branch",
  }];
  const sessionFile = join(sessionsRoot, "branch.jsonl");
  await writeFile(sessionFile, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
  const registry = new WorkspaceRegistry(root);
  const workspace = await registry.get("ts_001");
  const session = (await registry.listPersistedSessionIds(workspace)).sessions.get("session-branch");
  assert.ok(session);

  const page = await registry.readPersistedSessionMessages(workspace, session);
  assert.deepEqual(page.messageIds, ["00000001", "00000004"]);
  assert.match(JSON.stringify(page.messages), /root/);
  assert.match(JSON.stringify(page.messages), /active/);
  assert.doesNotMatch(JSON.stringify(page.messages), /abandoned/);

  await assert.rejects(
    () => registry.readPersistedSessionMessages(workspace, session, {
      before: "00000002",
      limit: 10,
    }),
    (error: unknown) => error instanceof HttpError && error.code === "session_history_cursor_invalid",
  );
});

test("registry rejects malformed, symbolic-link, and oversized session histories", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-unsafe-history-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  const header = JSON.stringify({
    type: "session",
    version: 3,
    id: "session-unsafe",
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  });
  const sessionFile = join(sessionsRoot, "unsafe.jsonl");
  await writeFile(sessionFile, `${header}\nnot-json\n`);
  const registry = new WorkspaceRegistry(root);
  const workspace = await registry.get("ts_001");
  let index = await registry.listPersistedSessionIds(workspace);
  const malformed = index.sessions.get("session-unsafe");
  assert.ok(malformed);
  await assert.rejects(
    () => registry.readPersistedSessionMessages(workspace, malformed),
    (error: unknown) => error instanceof HttpError && error.code === "session_history_unavailable",
  );

  const target = join(root, "target.jsonl");
  await writeFile(target, `${header}\n`);
  await rm(sessionFile);
  await symlink(target, sessionFile);
  await assert.rejects(
    () => registry.readPersistedSessionMessages(workspace, malformed),
    (error: unknown) => error instanceof HttpError && error.code === "session_history_not_found",
  );

  await rm(sessionFile);
  await writeFile(sessionFile, `${header}\n`);
  await truncate(sessionFile, 64 * 1024 * 1024 + 1);
  index = await registry.listPersistedSessionIds(workspace);
  assert.equal(index.complete, false);
  assert.equal(index.sessions.has("session-unsafe"), false);
});

test("registry rejects a duplicated message cursor", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-duplicate-cursor-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  const records = [{
    type: "session",
    version: 3,
    id: "session-duplicate",
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  }, {
    type: "message",
    id: "00000001",
    parentId: null,
    message: { role: "user", content: "first", timestamp: 1 },
  }, {
    type: "message",
    id: "00000001",
    parentId: "00000001",
    message: { role: "assistant", content: [{ type: "text", text: "second" }], timestamp: 2 },
  }];
  await writeFile(
    join(sessionsRoot, "duplicate.jsonl"),
    `${records.map((record) => JSON.stringify(record)).join("\n")}\n`,
  );
  const registry = new WorkspaceRegistry(root);
  const workspace = await registry.get("ts_001");
  const session = (await registry.listPersistedSessionIds(workspace)).sessions.get("session-duplicate");
  assert.ok(session);

  await assert.rejects(
    () => registry.readPersistedSessionMessages(workspace, session, {
      before: "00000001",
      limit: 10,
    }),
    (error: unknown) => error instanceof HttpError && error.code === "session_history_cursor_ambiguous",
  );
});

test("an incomplete index still returns its independently valid sessions", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-partial-index-"));
  const workspaceRoot = join(root, "ts_001");
  const sessionsRoot = join(workspaceRoot, ".pi", "sessions");
  await mkdir(sessionsRoot, { recursive: true });
  await writeFile(join(sessionsRoot, "valid.jsonl"), `${JSON.stringify({
    type: "session",
    version: 3,
    id: "session-valid",
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  })}\n`);
  await writeFile(join(sessionsRoot, "malformed.jsonl"), "not-json\n");
  const registry = new WorkspaceRegistry(root);

  const index = await registry.listPersistedSessionIds(await registry.get("ts_001"));
  assert.equal(index.complete, false);
  assert.deepEqual([...index.ids], ["session-valid"]);
});
