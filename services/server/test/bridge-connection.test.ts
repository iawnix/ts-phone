import assert from "node:assert/strict";
import { Socket } from "node:net";
import test from "node:test";
import { BridgeConnection } from "../src/bridge/bridge-connection.js";
import type { BridgeRegisterRecord } from "../src/bridge/protocol.js";

test("a close listener added after an early socket close still runs once", () => {
  const socket = new Socket();
  socket.destroy();
  const registration: BridgeRegisterRecord = {
    protocolVersion: "ts-phone-bridge/2",
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
