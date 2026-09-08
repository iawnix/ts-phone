import type {
  RuntimeState,
  SessionAccessMode,
  SessionRuntimeSnapshot,
  SessionSnapshot,
} from "../types.js";

export const BRIDGE_PROTOCOL_VERSION = "ts-phone-bridge/3" as const;
export const BRIDGE_WORKSPACE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
export const BRIDGE_ID_PATTERN = /^[A-Za-z0-9._:-]{1,160}$/;

interface BridgeEnvelope {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  workspaceId: string;
  sessionId: string;
  instanceEpoch: string;
  sessionGeneration: number;
}

export interface BridgeRegisterRecord extends BridgeEnvelope {
  type: "bridge.register";
  accessMode: SessionAccessMode;
  secret: string;
  workspaceRoot: string;
  pid: number;
  launchId?: string;
}

export interface BridgeHeartbeatRecord extends BridgeEnvelope {
  type: "bridge.heartbeat";
  sequence: number;
}

export interface BridgeSnapshotRecord extends BridgeEnvelope {
  type: "session.snapshot";
  sequence: number;
  snapshot: BridgeSessionSnapshot;
}

export interface BridgeSessionSnapshot extends SessionSnapshot {
  agentRunId?: string;
}

export interface BridgeEventRecord extends BridgeEnvelope {
  type: "event.publish";
  sequence: number;
  eventType: string;
  payload: unknown;
}

export interface BridgeCommandAckRecord extends BridgeEnvelope {
  type: "command.ack";
  requestId: string;
  ok: boolean;
  errorCode?: string;
}

export interface BridgeApprovalRequestRecord extends BridgeEnvelope {
  type: "approval.request";
  sequence: number;
  approvalId: string;
  turnId: string;
  toolCallId: string;
  toolName: string;
  preview: string;
  expiresAt: string;
}

export type BridgeClientRecord =
  | BridgeRegisterRecord
  | BridgeHeartbeatRecord
  | BridgeSnapshotRecord
  | BridgeEventRecord
  | BridgeCommandAckRecord
  | BridgeApprovalRequestRecord;

export interface BridgeRegisteredRecord {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  type: "bridge.registered";
  workspaceId: string;
  sessionId: string;
  instanceEpoch: string;
}

export interface BridgePromptCommand {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  type: "command.prompt";
  workspaceId: string;
  sessionId: string;
  instanceEpoch: string;
  sessionGeneration: number;
  requestId: string;
  clientMessageId: string;
  message: string;
}

export interface BridgeAbortCommand {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  type: "command.abort";
  workspaceId: string;
  sessionId: string;
  instanceEpoch: string;
  sessionGeneration: number;
  requestId: string;
  agentRunId: string;
}

export interface BridgeApprovalResponse {
  protocolVersion: typeof BRIDGE_PROTOCOL_VERSION;
  type: "approval.respond";
  workspaceId: string;
  sessionId: string;
  instanceEpoch: string;
  sessionGeneration: number;
  requestId: string;
  approvalId: string;
  approved: boolean;
}

export type BridgeServerRecord =
  | BridgeRegisteredRecord
  | BridgePromptCommand
  | BridgeAbortCommand
  | BridgeApprovalResponse;

export function parseBridgeClientRecord(value: unknown): BridgeClientRecord {
  const record = asObject(value, "Bridge record");
  if (record.protocolVersion !== BRIDGE_PROTOCOL_VERSION) {
    throw new Error("Unsupported bridge protocol version");
  }
  const type = requiredString(record.type, "type", 100);
  const workspaceId = requiredString(record.workspaceId, "workspaceId", 80);
  if (!BRIDGE_WORKSPACE_PATTERN.test(workspaceId)) throw new Error("Invalid bridge workspaceId");
  const instanceEpoch = requiredId(record.instanceEpoch, "instanceEpoch");
  const sessionId = requiredId(record.sessionId, "sessionId");
  const sessionGeneration = positiveInteger(record.sessionGeneration, "sessionGeneration");
  const envelope = {
    protocolVersion: BRIDGE_PROTOCOL_VERSION,
    workspaceId,
    sessionId,
    instanceEpoch,
    sessionGeneration,
  };

  switch (type) {
    case "bridge.register":
      return {
        ...envelope,
        type,
        accessMode: requiredAccessMode(record.accessMode),
        secret: requiredString(record.secret, "secret", 200),
        workspaceRoot: requiredString(record.workspaceRoot, "workspaceRoot", 4096),
        pid: positiveInteger(record.pid, "pid"),
        ...(record.launchId === undefined ? {} : { launchId: requiredId(record.launchId, "launchId") }),
      };
    case "bridge.heartbeat":
      return { ...envelope, type, sequence: positiveInteger(record.sequence, "sequence") };
    case "session.snapshot":
      return {
        ...envelope,
        type,
        sequence: positiveInteger(record.sequence, "sequence"),
        snapshot: parseSnapshot(record.snapshot),
      };
    case "event.publish":
      return {
        ...envelope,
        type,
        sequence: positiveInteger(record.sequence, "sequence"),
        eventType: requiredEventType(record.eventType),
        payload: record.payload,
      };
    case "command.ack": {
      const parsed: BridgeCommandAckRecord = {
        ...envelope,
        type,
        requestId: requiredId(record.requestId, "requestId"),
        ok: requiredBoolean(record.ok, "ok"),
      };
      if (record.errorCode !== undefined) parsed.errorCode = requiredId(record.errorCode, "errorCode");
      return parsed;
    }
    case "approval.request":
      return {
        ...envelope,
        type,
        sequence: positiveInteger(record.sequence, "sequence"),
        approvalId: requiredId(record.approvalId, "approvalId"),
        turnId: requiredId(record.turnId, "turnId"),
        toolCallId: requiredId(record.toolCallId, "toolCallId"),
        toolName: requiredString(record.toolName, "toolName", 160),
        preview: requiredString(record.preview, "preview", 4_000),
        expiresAt: requiredDate(record.expiresAt, "expiresAt"),
      };
    default:
      throw new Error(`Unsupported bridge record type: ${type}`);
  }
}

function parseSnapshot(value: unknown): BridgeSessionSnapshot {
  const snapshot = asObject(value, "snapshot");
  assertOnlyKeys(
    snapshot,
    [
      "sessionId",
      "sessionName",
      "model",
      "promptProblem",
      "runtime",
      "thinkingLevel",
      "isStreaming",
      "agentRunId",
      "messages",
      "messageIds",
      "hasMore",
      "nextBefore",
    ],
    "snapshot",
  );
  const sessionId = requiredId(snapshot.sessionId, "sessionId");
  const isStreaming = requiredBoolean(snapshot.isStreaming, "isStreaming");
  if (!Array.isArray(snapshot.messages)) throw new Error("snapshot.messages must be an array");
  const parsed: BridgeSessionSnapshot = { sessionId, isStreaming, messages: snapshot.messages };
  if (isStreaming) {
    parsed.agentRunId = requiredId(snapshot.agentRunId, "snapshot.agentRunId");
  } else if (snapshot.agentRunId !== undefined) {
    throw new Error("snapshot.agentRunId is only valid while streaming");
  }
  if (snapshot.messageIds !== undefined) {
    if (!Array.isArray(snapshot.messageIds) || snapshot.messageIds.length !== snapshot.messages.length) {
      throw new Error("snapshot.messageIds must align with snapshot.messages");
    }
    const messageIds = snapshot.messageIds.map((value) => requiredMessageId(value, "messageId"));
    if (new Set(messageIds).size !== messageIds.length) {
      throw new Error("snapshot.messageIds must be unique");
    }
    parsed.messageIds = messageIds;
  }
  if (snapshot.hasMore !== undefined) parsed.hasMore = requiredBoolean(snapshot.hasMore, "hasMore");
  if (snapshot.nextBefore !== undefined) {
    parsed.nextBefore = requiredMessageId(snapshot.nextBefore, "nextBefore");
  }
  if (parsed.hasMore === true
    && (!parsed.messageIds?.length || parsed.nextBefore !== parsed.messageIds[0])) {
    throw new Error("snapshot.nextBefore must identify the first message when hasMore is true");
  }
  if (parsed.hasMore !== true && parsed.nextBefore !== undefined) {
    throw new Error("snapshot.nextBefore requires hasMore=true");
  }
  if (snapshot.sessionName !== undefined) parsed.sessionName = requiredString(snapshot.sessionName, "sessionName", 500);
  if (snapshot.model !== undefined) parsed.model = requiredString(snapshot.model, "model", 500);
  if (snapshot.promptProblem !== undefined) {
    if (snapshot.promptProblem !== "model_unavailable" && snapshot.promptProblem !== "model_auth_missing"
      && snapshot.promptProblem !== "model_storage_unavailable" && snapshot.promptProblem !== "model_check_failed") {
      throw new Error("snapshot.promptProblem is invalid");
    }
    parsed.promptProblem = snapshot.promptProblem;
  }
  if (snapshot.runtime !== undefined) parsed.runtime = parseSessionRuntime(snapshot.runtime);
  if (snapshot.thinkingLevel !== undefined) {
    parsed.thinkingLevel = requiredString(snapshot.thinkingLevel, "thinkingLevel", 100);
  }
  return parsed;
}

function parseSessionRuntime(value: unknown): SessionRuntimeSnapshot {
  const runtime = asObject(value, "snapshot.runtime");
  assertOnlyKeys(runtime, ["schemaVersion", "model", "context", "updatedAt"], "snapshot.runtime");
  if (runtime.schemaVersion !== "ts-phone-session-runtime/1") {
    throw new Error("Unsupported session runtime schema");
  }
  const rawModel = asObject(runtime.model, "snapshot.runtime.model");
  assertOnlyKeys(rawModel, ["provider", "id"], "snapshot.runtime.model");
  const parsed: SessionRuntimeSnapshot = {
    schemaVersion: "ts-phone-session-runtime/1",
    model: {
      provider: requiredString(rawModel.provider, "runtime.model.provider", 160),
      id: requiredString(rawModel.id, "runtime.model.id", 240),
    },
    updatedAt: requiredDate(runtime.updatedAt, "runtime.updatedAt"),
  };
  if (runtime.context !== undefined) {
    const rawContext = asObject(runtime.context, "snapshot.runtime.context");
    assertOnlyKeys(
      rawContext,
      ["usedTokens", "limitTokens", "measurement"],
      "snapshot.runtime.context",
    );
    if (rawContext.measurement !== "pi_estimate") {
      throw new Error("runtime.context.measurement is unsupported");
    }
    parsed.context = {
      usedTokens: nullableNonNegativeInteger(rawContext.usedTokens, "runtime.context.usedTokens"),
      limitTokens: positiveInteger(rawContext.limitTokens, "runtime.context.limitTokens"),
      measurement: "pi_estimate",
    };
  }
  return parsed;
}

export function isRuntimeState(value: unknown): value is RuntimeState {
  return value === "offline" || value === "connecting" || value === "idle"
    || value === "running" || value === "recovery_required";
}

function asObject(value: unknown, name: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} must be an object`);
  return value as Record<string, unknown>;
}

function assertOnlyKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
  name: string,
): void {
  const unexpected = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unexpected.length > 0) throw new Error(`${name} contains unsupported fields`);
}

function requiredString(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new Error(`${name} must be a non-empty bounded string`);
  }
  return value;
}

function requiredId(value: unknown, name: string): string {
  const parsed = requiredString(value, name, 160);
  if (!BRIDGE_ID_PATTERN.test(parsed)) throw new Error(`${name} contains unsupported characters`);
  return parsed;
}

function requiredMessageId(value: unknown, name: string): string {
  const parsed = requiredString(value, name, 8);
  if (!/^[0-9a-f]{8}$/.test(parsed)) throw new Error(`${name} is not a Pi message entry id`);
  return parsed;
}

function requiredEventType(value: unknown): string {
  const parsed = requiredString(value, "eventType", 100);
  if (!/^[A-Za-z0-9_.-]+$/.test(parsed)) throw new Error("eventType contains unsupported characters");
  return parsed;
}

function positiveInteger(value: unknown, name: string): number {
  if (!Number.isSafeInteger(value) || (value as number) <= 0) throw new Error(`${name} must be a positive integer`);
  return value as number;
}

function nullableNonNegativeInteger(value: unknown, name: string): number | null {
  if (value === null) return null;
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new Error(`${name} must be null or a non-negative integer`);
  }
  return value as number;
}

function requiredBoolean(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") throw new Error(`${name} must be a boolean`);
  return value;
}

function requiredDate(value: unknown, name: string): string {
  const parsed = requiredString(value, name, 100);
  if (!Number.isFinite(Date.parse(parsed))) throw new Error(`${name} must be an ISO date-time`);
  return parsed;
}

function requiredAccessMode(value: unknown): SessionAccessMode {
  if (value !== "controller" && value !== "observer") {
    throw new Error("accessMode must be controller or observer");
  }
  return value;
}
