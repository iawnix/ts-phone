export const API_VERSION = "ts-phone-api/3" as const;
export const EVENT_VERSION = "ts-phone-events/3" as const;

export type RuntimeState =
  | "offline"
  | "connecting"
  | "idle"
  | "running"
  | "recovery_required";

export type SessionAccessMode = "controller" | "observer";

export interface WorkspaceSummary {
  id: string;
  name: string;
  runtimeState: RuntimeState;
  isStreaming: boolean;
  liveSessionCount: number;
  sessionCount: number;
}

export interface SessionSummary {
  sessionId: string;
  sessionRevision: string;
  sessionName?: string;
  model?: string;
  runtimeState: RuntimeState;
  isStreaming: boolean;
  accessMode: SessionAccessMode;
  historyAvailable?: boolean;
  historyOnly?: boolean;
  canPrompt?: boolean;
}

export interface SessionSnapshot {
  sessionId: string;
  sessionName?: string;
  model?: string;
  thinkingLevel?: string;
  isStreaming: boolean;
  messages: unknown[];
}

export interface MessageSnapshot {
  sessionId: string;
  sessionRevision: string;
  messages: unknown[];
  lastEventId: string;
}

export interface EventEnvelope {
  protocolVersion: typeof EVENT_VERSION;
  id: string;
  workspaceId: string;
  sessionId: string;
  sessionRevision: string;
  instanceEpoch: string | null;
  sessionGeneration: number | null;
  type: string;
  payload: unknown;
  at: string;
}

export interface PromptInput {
  clientMessageId: string;
  sessionRevision: string;
  message: string;
}

export interface ApprovalInput {
  approved: boolean;
  sessionRevision: string;
}

export interface SessionCommandInput {
  sessionRevision: string;
}
