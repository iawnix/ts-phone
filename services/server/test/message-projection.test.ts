import assert from "node:assert/strict";
import test from "node:test";
import {
  MAX_SNAPSHOT_BYTES,
  projectSnapshotMessagePage,
  projectSnapshotMessages,
  projectMessage,
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

test('empty assistant outcomes remain explicit without leaking private content', () => {
  const records = [
    { role: 'assistant', content: [], stopReason: 'error', errorMessage: 'private provider detail' },
    { role: 'assistant', content: [], stopReason: 'aborted' },
    { role: 'assistant', content: [{ type: 'thinking', thinking: 'private reasoning' }] },
    { role: 'assistant', content: [] },
  ];
  const page = projectSnapshotMessagePage(records, ['00000001', '00000002', '00000003', '00000004']);
  assert.deepEqual(page.messageIds, ['00000001', '00000002', '00000003', '00000004']);
  assert.deepEqual(page.messages.map((value) => (value as { outputState: string }).outputState),
    ['failed', 'aborted', 'not_displayed', 'empty']);
  assert.ok(!JSON.stringify(page).includes('private'));
  assert.deepEqual(projectSnapshotMessages(page.messages), page.messages);
});

test('plain assistant text and partial failures preserve visible content', () => {
  assert.deepEqual(projectMessage({ role: 'assistant', content: 'A readable reply' }), {
    role: 'assistant', content: [{ type: 'text', text: 'A readable reply' }], timestamp: undefined,
  });
  assert.deepEqual(projectMessage({ role: 'assistant', content: [{ type: 'text', text: 'Partial reply' }], stopReason: 'error' }), {
    role: 'assistant', content: [{ type: 'text', text: 'Partial reply' }], timestamp: undefined, outputState: 'failed',
  });
});
