export const API_VERSION = "ts-phone-api/3" as const;
export const EVENT_VERSION = "ts-phone-events/3" as const;
export const SERVICE_VERSION = "0.5.1" as const;

export type RuntimeState =
  | "offline"
  | "connecting"
  | "idle"
  | "running"
  | "recovery_required";

export type SessionAccessMode = "controller" | "observer";

export type SessionCapability =
  | "history.messages"
  | "history.timeline"
  | "history.pagination"
  | "history.branches"
  | "activity.tools"
  | "activity.subagents"
  | "activity.research"
  | "command.prompt"
  | "command.abort"
  | "interaction.approval";

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
  runtime?: SessionRuntimeSnapshot;
  runtimeState: RuntimeState;
  isStreaming: boolean;
  accessMode: SessionAccessMode;
  historyAvailable?: boolean;
  historyOnly?: boolean;
  canPrompt?: boolean;
  capabilities: SessionCapability[];
}

export interface SessionRuntimeSnapshot {
  schemaVersion: "ts-phone-session-runtime/1";
  model: {
    provider: string;
    id: string;
  };
  context?: {
    usedTokens: number | null;
    limitTokens: number;
    measurement: "pi_estimate";
  };
  updatedAt: string;
}

export interface SessionSnapshot {
  sessionId: string;
  sessionName?: string;
  model?: string;
  runtime?: SessionRuntimeSnapshot;
  thinkingLevel?: string;
  isStreaming: boolean;
  messages: unknown[];
  messageIds?: string[];
  hasMore?: boolean;
  nextBefore?: string;
}

export interface MessagePage {
  messages: unknown[];
  messageIds?: string[];
  hasMore: boolean;
  nextBefore?: string;
}

export interface MessageSnapshot extends MessagePage {
  sessionId: string;
  sessionRevision: string;
  lastEventId: string;
}

export interface MessagePageRequest {
  before?: string;
  limit: number;
}

export interface TimelinePageRequest extends MessagePageRequest {
  branch?: string;
}

export type TimelineActivityCategory =
  | "subagent"
  | "research"
  | "review"
  | "workspace"
  | "configuration"
  | "context"
  | "system";

export type TimelineActivityStatus = "completed" | "failed" | "recorded";

export interface TimelineActivity {
  category: TimelineActivityCategory;
  status: TimelineActivityStatus;
  title: string;
  role?: string;
  operation?: string;
  nodeRefs?: string[];
  detail?: string;
  stage?: string;
  durationMs?: number;
  totalTokens?: number;
  retrySafe?: boolean;
  reference?: string;
  at?: string;
}

export type TimelineItem = {
  id: string;
  turnId?: string;
} & (
  | { kind: "message"; message: unknown }
  | { kind: "activity"; activity: TimelineActivity }
);

export interface TimelineBranchSummary {
  id: string;
  active: boolean;
  itemCount: number;
  messageCount: number;
  activityCount: number;
  turnCount: number;
  name?: string;
  updatedAt?: string;
}

export interface TimelineHistorySummary {
  totalItems: number;
  messageCount: number;
  activityCount: number;
  turnCount: number;
  branchCount: number;
  activeBranchId?: string;
  selectedBranchId?: string;
  branches: TimelineBranchSummary[];
}

export interface TimelinePage {
  items: TimelineItem[];
  history: TimelineHistorySummary;
  hasMore: boolean;
  nextBefore?: string;
}

export interface TimelineSnapshot extends TimelinePage {
  schemaVersion: "ts-phone-timeline/1";
  sessionId: string;
  sessionRevision: string;
  lastEventId: string;
  capabilities: SessionCapability[];
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
