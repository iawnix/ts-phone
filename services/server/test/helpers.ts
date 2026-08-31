import { mkdir, writeFile } from "node:fs/promises";
import { createConnection, type Socket } from "node:net";
import { join } from "node:path";
import type { ServerConfig } from "../src/config.js";
import { readBridgeSecret } from "../src/security.js";

export interface FakeBridge {
  sessionId: string;
  sessionFile: string;
  messages: unknown[];
  receivedCommands: Array<Record<string, unknown>>;
  publish(eventType: string, payload: unknown): void;
  publishSnapshot(isStreaming?: boolean, includeRuntime?: boolean): void;
  requestApproval(input: {
    approvalId: string;
    turnId: string;
    toolCallId: string;
    toolName: string;
    preview: string;
  }): void;
  close(): Promise<void>;
}

export async function connectFakeBridge(
  config: ServerConfig,
  workspaceId: string,
  workspaceRoot: string,
  options: {
    sessionId?: string;
    accessMode?: "controller" | "observer";
    instanceEpoch?: string;
  } = {},
): Promise<FakeBridge> {
  const socket = createConnection(config.bridgeSocketPath);
  socket.setEncoding("utf8");
  await new Promise<void>((resolve, reject) => {
    socket.once("connect", resolve);
    socket.once("error", reject);
  });
  const secret = await readBridgeSecret(config.bridgeSecretPath);
  const sessionId = options.sessionId || "session-test";
  const accessMode = options.accessMode || "controller";
  const instanceEpoch = options.instanceEpoch || "11111111-1111-4111-8111-111111111111";
  const sessionGeneration = 1;
  const sessionDirectory = join(workspaceRoot, ".pi", "sessions");
  const sessionFile = join(sessionDirectory, `${sessionId}.jsonl`);
  await mkdir(sessionDirectory, { recursive: true });
  await writeFile(sessionFile, `${JSON.stringify({
    type: "session",
    version: 3,
    id: sessionId,
    timestamp: new Date().toISOString(),
    cwd: workspaceRoot,
  })}\n`);
  const messages: unknown[] = [userMessage("existing")];
  const receivedCommands: Array<Record<string, unknown>> = [];
  let sequence = 0;
  let buffer = "";
  let didRegister = false;
  let registeredResolve: (() => void) | undefined;
  let registeredReject: ((error: Error) => void) | undefined;
  const registered = new Promise<void>((resolve, reject) => {
    registeredResolve = resolve;
    registeredReject = reject;
  });
  socket.once("close", () => {
    if (!didRegister) registeredReject?.(new Error("Bridge registration was rejected"));
  });

  const envelope = () => ({
    protocolVersion: "ts-phone-bridge/2",
    workspaceId,
    sessionId,
    instanceEpoch,
    sessionGeneration,
  });
  const write = (record: Record<string, unknown>) => socket.write(`${JSON.stringify(record)}\n`);
  const publish = (eventType: string, payload: unknown) => {
    sequence += 1;
    write({ ...envelope(), type: "event.publish", sequence, eventType, payload });
  };
  const publishSnapshot = (isStreaming = false, includeRuntime = true) => {
    sequence += 1;
    const firstIndex = Math.max(0, messages.length - 500);
    const boundedMessages = messages.slice(firstIndex);
    const messageIds = boundedMessages.map((_, index) => (
      (firstIndex + index).toString(16).padStart(8, "0")
    ));
    const hasMore = firstIndex > 0;
    write({
      ...envelope(),
      type: "session.snapshot",
      sequence,
      snapshot: {
        sessionId,
        sessionName: `Fake ${sessionId}`,
        model: "test/fake-model",
        ...(includeRuntime ? {
          runtime: {
            schemaVersion: "ts-phone-session-runtime/1",
            model: { provider: "test", id: "fake-model" },
            context: {
              usedTokens: 78_214,
              limitTokens: 128_000,
              measurement: "pi_estimate",
            },
            updatedAt: "2026-08-31T06:32:18.000Z",
          },
        } : {}),
        isStreaming,
        messages: boundedMessages,
        messageIds,
        hasMore,
        ...(hasMore ? { nextBefore: messageIds[0] } : {}),
      },
    });
  };
  const acknowledge = (requestId: unknown, ok = true) => write({
    ...envelope(),
    type: "command.ack",
    requestId,
    ok,
  });

  socket.on("data", (chunk: string | Buffer) => {
    buffer += chunk.toString();
    while (true) {
      const newline = buffer.indexOf("\n");
      if (newline < 0) break;
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      const record = JSON.parse(line) as Record<string, unknown>;
      if (record.type === "bridge.registered") {
        didRegister = true;
        registeredResolve?.();
        publishSnapshot();
        continue;
      }
      receivedCommands.push(record);
      if (record.type === "command.prompt") {
        const message = String(record.message);
        messages.push(userMessage(message));
        publish("input", {
          type: "input",
          text: message,
          source: "extension",
          origin: "phone",
          clientMessageId: record.clientMessageId,
        });
        acknowledge(record.requestId);
        publish("agent_start", { type: "agent_start" });
        publish("message_start", { type: "message_start", message: { role: "assistant", content: [] } });
        publish("message_update", {
          type: "message_update",
          assistantMessageEvent: { type: "text_delta", delta: `reply:${message}` },
        });
        const assistant = assistantMessage(`reply:${message}`);
        messages.push(assistant);
        publish("message_end", { type: "message_end", message: assistant });
        publish("agent_settled", { type: "agent_settled" });
        publishSnapshot();
      } else if (record.type === "command.abort") {
        acknowledge(record.requestId);
        publish("agent_settled", { type: "agent_settled" });
        publishSnapshot();
      } else if (record.type === "approval.respond") {
        acknowledge(record.requestId);
      }
    }
  });

  write({
    ...envelope(),
    type: "bridge.register",
    accessMode,
    secret,
    workspaceRoot,
    pid: process.pid,
  });
  await registered;

  return {
    sessionId,
    sessionFile,
    messages,
    receivedCommands,
    publish,
    publishSnapshot,
    requestApproval(input) {
      sequence += 1;
      write({
        ...envelope(),
        type: "approval.request",
        sequence,
        ...input,
        expiresAt: new Date(Date.now() + 60_000).toISOString(),
      });
    },
    close: () => closeSocket(socket),
  };
}

function userMessage(text: string): unknown {
  return { role: "user", content: [{ type: "text", text }], timestamp: Date.now() };
}

function assistantMessage(text: string): unknown {
  return {
    role: "assistant",
    content: [{ type: "text", text }],
    provider: "test",
    model: "fake-model",
    timestamp: Date.now(),
  };
}

function closeSocket(socket: Socket): Promise<void> {
  if (socket.destroyed) return Promise.resolve();
  return new Promise((resolve) => {
    socket.once("close", resolve);
    socket.end();
  });
}
