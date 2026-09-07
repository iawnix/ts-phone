export const API_VERSION = "ts-phone-api/4" as const;
export const EVENT_VERSION = "ts-phone-events/3" as const;
export const SERVICE_VERSION = "0.8.0" as const;

export type RuntimeState =
  | "offline"
  | "connecting"
  | "idle"
  | "running"
  | "recovery_required";

export type SessionAccessMode = "controller" | "observer";
export type RuntimeOwner = "host" | "external";
export type LifecycleState = "active" | "archived" | "trashed";

export type SessionCapability =
  | "history.messages"
  | "history.timeline"
  | "history.pagination"
  | "history.seek"
  | "history.branches"
  | "activity.tools"
  | "activity.subagents"
  | "activity.research"
  | "session.activate_mode"
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
  lifecycleState: LifecycleState;
  managementRevision: string;
  managed: boolean;
  updatedAt?: string;
  deletedAt?: string;
}

export interface SessionSummary {
  sessionId: string;
  sessionRevision: string;
  activeAgentRunId: string | null;
  sessionName?: string;
  model?: string;
  promptProblem?: PromptProblem;
  runtime?: SessionRuntimeSnapshot;
  runtimeState: RuntimeState;
  isStreaming: boolean;
  accessMode: SessionAccessMode;
  currentAccessMode?: SessionAccessMode | null;
  runtimeOwner?: RuntimeOwner | null;
  activation?: SessionActivation;
  historyAvailable?: boolean;
  historyOnly?: boolean;
  canPrompt?: boolean;
  capabilities: SessionCapability[];
  lifecycleState: LifecycleState;
  managementRevision: string;
  managed: boolean;
  canActivate: boolean;
  updatedAt?: string;
  deletedAt?: string;
}

export interface CreateWorkspaceInput {
  name: string;
}

export interface CreateSessionInput {
  name?: string;
  model?: string;
  accessMode: SessionAccessMode;
}

export interface RenameInput {
  name: string;
  managementRevision: string;
}

export interface LifecycleInput {
  managementRevision: string;
}

export interface PurgeInput extends LifecycleInput {
  confirmation: string;
}

export interface ActivateInput extends LifecycleInput {
  accessMode?: SessionAccessMode;
  requestId?: string;
  switchFrom?: { sessionId: string; sessionRevision: string };
}

export interface SessionActivation {
  modes: SessionAccessMode[];
  problem?: string;
  conflict?: {
    sessionId: string;
    sessionRevision: string;
    sessionName?: string;
    owner: RuntimeOwner;
    switchable: boolean;
  };
}

export interface WorkspaceCreationResult {
  workspace: WorkspaceSummary;
  session: SessionSummary;
}

export interface WorkspaceDeletionPreflight {
  workspaceId: string;
  managementRevision: string;
  activeWorkers: number;
  remoteCalculations: number;
  pendingApprovals: number;
  unresolvedRemoteEffects: number;
  canDelete: boolean;
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

export type PromptProblem = "model_unavailable" | "model_auth_missing" | "model_check_failed";

export interface SessionSnapshot {
  sessionId: string;
  sessionName?: string;
  model?: string;
  promptProblem?: PromptProblem;
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
  hasLater?: boolean;
  nextAfter?: string;
}

export interface MessageSnapshot extends MessagePage {
  sessionId: string;
  sessionRevision: string;
  activeAgentRunId: string | null;
  lastEventId: string;
}

export interface MessagePageRequest {
  before?: string;
  after?: string;
  edge?: "start";
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
  hasLater?: boolean;
  nextAfter?: string;
}

export interface TimelineSnapshot extends TimelinePage {
  schemaVersion: "ts-phone-timeline/1";
  sessionId: string;
  sessionRevision: string;
  activeAgentRunId: string | null;
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

export interface AbortInput {
  sessionRevision: string;
  agentRunId: string;
}
