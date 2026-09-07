import assert from "node:assert/strict";
import test from "node:test";
import { historyPage } from "../src/history-page.js";
import { MAX_SNAPSHOT_BYTES } from "../src/message-projection.js";

test("history pages seek to both ends and traverse without gaps or duplicate cursors", () => {
  const records = Array.from({ length: 505 }, (_, i) => ({ id: i.toString(16).padStart(8, "0") }));
  const first = historyPage(records, { edge: "start", limit: 2 });
  assert.deepEqual(first.records, records.slice(0, 2));
  assert.equal(first.hasMore, false);
  assert.equal(first.hasLater, true);
  assert.equal(first.nextAfter, records[1]!.id);
  const next = historyPage(records, { after: first.nextAfter!, limit: 2 });
  assert.deepEqual(next.records, records.slice(2, 4));
  const previous = historyPage(records, { before: next.nextBefore!, limit: 2 });
  assert.deepEqual(previous.records, first.records);
  const latest = historyPage(records, { limit: 2 });
  assert.deepEqual(latest.records, records.slice(-2));
  assert.equal(latest.hasLater, false);
  assert.equal(latest.nextAfter, undefined);
  assert.deepEqual(historyPage([], { edge: "start", limit: 2 }).records, []);
  assert.throws(() => historyPage(records, { after: "missing", limit: 2 }), { code: "session_history_cursor_invalid" });
  assert.throws(() => historyPage(records, { edge: "start", before: records[0]!.id, limit: 2 }), { code: "invalid_history_query" });
});

test("forward and reverse history pages enforce a byte budget", () => {
  const records = Array.from({ length: 5 }, (_, i) => ({ id: String(i), text: "x".repeat(MAX_SNAPSHOT_BYTES / 3) }));
  for (const request of [{ edge: "start" as const, limit: 5 }, { limit: 5 }]) {
    const page = historyPage(records, request);
    assert.equal(page.records.length, 2);
    assert.ok(Buffer.byteLength(JSON.stringify(page.records)) <= MAX_SNAPSHOT_BYTES);
  }
});
