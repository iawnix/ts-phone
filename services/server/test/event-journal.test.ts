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
