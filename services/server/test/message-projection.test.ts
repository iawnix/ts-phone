import assert from "node:assert/strict";
import test from "node:test";
import {
  MAX_SNAPSHOT_BYTES,
  projectSnapshotMessagePage,
  projectSnapshotMessages,
} from "../src/message-projection.js";

test("message projection never returns a snapshot above its byte limit", () => {
  const oversized = projectSnapshotMessages([{
    role: "assistant",
    content: [{
      type: "toolCall",
      name: "large-tool",
      arguments: { payload: "x".repeat(MAX_SNAPSHOT_BYTES) },
    }],
    timestamp: 1,
  }]);
  assert.deepEqual(oversized, []);
  const oversizedPage = projectSnapshotMessagePage([{
    role: "assistant",
    content: [{
      type: "toolCall",
      name: "large-tool",
      arguments: { payload: "x".repeat(MAX_SNAPSHOT_BYTES) },
    }],
    timestamp: 1,
  }], ["00000001"]);
  assert.deepEqual(oversizedPage.messages, []);
  assert.deepEqual(oversizedPage.messageIds, []);
  assert.equal(oversizedPage.omitted, 1);

  const bounded = projectSnapshotMessages([{
    role: "assistant",
    content: [{ type: "text", text: "visible" }],
    timestamp: 2,
  }]);
  assert.ok(Buffer.byteLength(JSON.stringify(bounded)) <= MAX_SNAPSHOT_BYTES);
});
