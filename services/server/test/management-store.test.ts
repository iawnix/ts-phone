import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { ManagementStore } from "../src/management-store.js";
import { HttpError } from "../src/errors.js";

test("metadata capacity failure preserves both disk and in-memory state", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-management-capacity-"));
  const store = await ManagementStore.open(root);
  const workspace = await store.createWorkspace("ts_001", "Project", "session_1", {
    accessMode: "controller", name: "研究".repeat(60),
  });
  // Compact, valid input below the read cap can expand beyond the write cap.
  // This also catches byte-vs-character counting with multi-byte display names.
  workspace.sessions = Object.fromEntries(Array.from({ length: 1650 }, (_, i) => (
    [`session_${i + 1}`, structuredClone(workspace.sessions.session_1)]
  )));
  const document = { schemaVersion: "ts-phone-management/1", workspaces: { ts_001: workspace } };
  const before = JSON.stringify(document);
  assert.ok(Buffer.byteLength(before) < 1024 * 1024);
  assert.ok(Buffer.byteLength(JSON.stringify(document, null, 2)) > 1024 * 1024);
  const path = join(root, "management.json");
  await writeFile(path, before, { mode: 0o600 });
  const loaded = await ManagementStore.open(root);
  await assert.rejects(
    () => loaded.renameWorkspace("ts_001", "Project", workspace.managementRevision, "Renamed"),
    (error: unknown) => error instanceof HttpError && error.code === "management_capacity_exceeded",
  );
  assert.equal(await readFile(path, "utf8"), before);
  assert.deepEqual(loaded.workspace("ts_001"), workspace);
  assert.deepEqual((await ManagementStore.open(root)).workspace("ts_001"), workspace);
  assert.deepEqual(await readdir(root), ["management.json"]);
});
