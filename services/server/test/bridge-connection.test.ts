import assert from "node:assert/strict";
import { Socket } from "node:net";
import test from "node:test";
import { BridgeConnection } from "../src/bridge/bridge-connection.js";
import {
  parseBridgeClientRecord,
  type BridgeRegisterRecord,
} from "../src/bridge/protocol.js";

test("a close listener added after an early socket close still runs once", () => {
  const socket = new Socket();
  socket.destroy();
  const registration: BridgeRegisterRecord = {
    protocolVersion: "ts-phone-bridge/3",
    type: "bridge.register",
    workspaceId: "ts_001",
    sessionId: "session-1",
    workspaceRoot: "/tmp/ts_001",
    accessMode: "controller",
    instanceEpoch: "11111111-1111-4111-8111-111111111111",
    sessionGeneration: 1,
    secret: "a".repeat(48),
    pid: 1234,
  };
  const connection = new BridgeConnection(socket, registration, 1_000);
  let closeCount = 0;

  connection.onClose(() => {
    closeCount += 1;
  });

  assert.equal(closeCount, 1);
});

test("bridge runtime snapshots accept Pi estimates and reject unknown fields", () => {
  const record = {
    protocolVersion: "ts-phone-bridge/3",
    type: "session.snapshot",
    workspaceId: "ts_001",
    sessionId: "session-1",
    instanceEpoch: "11111111-1111-4111-8111-111111111111",
    sessionGeneration: 1,
    sequence: 1,
    snapshot: {
      sessionId: "session-1",
      isStreaming: false,
      messages: [],
      runtime: {
        schemaVersion: "ts-phone-session-runtime/1",
        model: { provider: "cpa", id: "gpt-5.6-sol" },
        context: {
          usedTokens: null,
          limitTokens: 128_000,
          measurement: "pi_estimate",
        },
        updatedAt: "2026-08-31T06:32:18.000Z",
      },
    },
  };
  const parsed = parseBridgeClientRecord(record);
  assert.equal(parsed.type, "session.snapshot");
  assert.equal(parsed.snapshot.runtime?.context?.usedTokens, null);

  assert.throws(
    () => parseBridgeClientRecord({
      ...record,
      snapshot: {
        ...record.snapshot,
        runtime: { ...record.snapshot.runtime, endpoint: "must-not-pass" },
      },
    }),
    /unsupported fields/,
  );
});

test("bridge v3 binds running snapshots to one agent run and rejects bridge v2", () => {
  const base = {
    protocolVersion: "ts-phone-bridge/3",
    type: "session.snapshot",
    workspaceId: "ts_001",
    sessionId: "session-1",
    instanceEpoch: "11111111-1111-4111-8111-111111111111",
    sessionGeneration: 1,
    sequence: 1,
    snapshot: {
      sessionId: "session-1",
      isStreaming: true,
      messages: [],
    },
  };

  assert.throws(
    () => parseBridgeClientRecord({ ...base, protocolVersion: "ts-phone-bridge/2" }),
    /Unsupported bridge protocol version/,
  );
  assert.throws(() => parseBridgeClientRecord(base), /snapshot\.agentRunId/);
  assert.equal(parseBridgeClientRecord({
    ...base,
    snapshot: { ...base.snapshot, agentRunId: "run-1-1" },
  }).type, "session.snapshot");
  assert.throws(
    () => parseBridgeClientRecord({
      ...base,
      snapshot: { ...base.snapshot, isStreaming: false, agentRunId: "run-1-1" },
    }),
    /only valid while streaming/,
  );
});
