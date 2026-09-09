import assert from "node:assert/strict";
import test from "node:test";
import { EventJournal } from "../src/event-journal.js";

test("event journal is bounded by both record count and serialized bytes", () => {
  const journal = new EventJournal("ts_001", "session-test", 100, 1_000);
  for (let index = 0; index < 10; index += 1) {
    journal.publish("message_update", { index, text: "x".repeat(400) });
  }

  const events = journal.since(undefined);
  assert.ok(events.length < 10);
  assert.equal((events.at(-1)?.payload as { index: number }).index, 9);
});

test("event replay reports a cursor gap and retains the latest snapshot baseline", () => {
  const journal = new EventJournal("ts_001", "session-test", 3, 50_000);
  const snapshot = journal.publish("session.snapshot", { messages: ["before"] });
  journal.publish("message_update", { index: 1 });
  journal.publish("message_update", { index: 2 });
  journal.publish("message_update", { index: 3 });

  assert.equal(journal.latestSnapshot?.id, snapshot.id);
  assert.equal(journal.replay(snapshot.id).needsSnapshot, false);
  assert.equal(journal.replay(snapshot.id).events.length, 3);
  assert.equal(journal.replay("invalid-cursor").needsSnapshot, true);
  assert.equal(journal.replay("00000000-0000-0000-0000-000000000000:1").needsSnapshot, true);
});
