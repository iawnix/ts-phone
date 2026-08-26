import type { Socket } from "node:net";
import type { ServerConfig } from "../config.js";
import { EventJournal } from "../event-journal.js";
import { HttpError, RuntimeError } from "../errors.js";
import { appendProjectedMessage, projectSnapshotMessages } from "../message-projection.js";
import { secretsEqual } from "../security.js";
import type {
  ApprovalInput,
  MessageSnapshot,
  PromptInput,
  RuntimeState,
  SessionCommandInput,
  SessionSnapshot,
  SessionSummary,
  WorkspaceSummary,
} from "../types.js";
import {
  WorkspaceRegistry,
  type PersistedSession,
  type RegisteredWorkspace,
} from "../workspace-registry.js";
import { BridgeConnection } from "../bridge/bridge-connection.js";
import { BRIDGE_PROTOCOL_VERSION } from "../bridge/protocol.js";
import type {
  BridgeApprovalRequestRecord,
  BridgeClientRecord,
  BridgeRegisterRecord,
} from "../bridge/protocol.js";

interface WorkspaceRecord {
  workspace: RegisteredWorkspace;
  sessions: Map<string, SessionRecord>;
}

interface SessionRecord {
  sessionId: string;
  journal: EventJournal;
  state: RuntimeState;
  accessMode: "controller" | "observer";
  persisted?: PersistedSession;
  connection?: BridgeConnection;
  snapshot?: SessionSnapshot;
  snapshotEventId?: string;
  messageCommands: Map<string, Promise<void>>;
}

interface PendingApproval {
  connection: BridgeConnection;
  request: BridgeApprovalRequestRecord;
  sessionRevision: string;
}

export class WorkspaceHub {
  readonly #config: ServerConfig;
  readonly #registry: WorkspaceRegistry;
  readonly #bridgeSecret: string;
  readonly #records = new Map<string, WorkspaceRecord>();
  readonly #approvals = new Map<string, PendingApproval>();
  readonly #staleTimer: NodeJS.Timeout;

  constructor(
    config: ServerConfig,
    bridgeSecret: string,
    registry = new WorkspaceRegistry(config.workspaceRoot),
  ) {
    this.#config = config;
    this.#bridgeSecret = bridgeSecret;
    this.#registry = registry;
    this.#staleTimer = setInterval(() => this.#closeStaleConnections(), 10_000);
    this.#staleTimer.unref();
  }

  async listWorkspaces(): Promise<WorkspaceSummary[]> {
    const workspaces = await this.#registry.list();
    const registeredIds = new Set(workspaces.map((workspace) => workspace.id));
    for (const workspaceId of this.#records.keys()) {
      if (!registeredIds.has(workspaceId)) this.#discardWorkspace(workspaceId);
    }
    const summaries: WorkspaceSummary[] = [];
    for (const registered of workspaces) {
      const workspace = this.#ensureWorkspace(registered);
      await this.#reconcileSessions(workspace);
      summaries.push(this.#workspaceSummary(workspace));
    }
    return summaries;
  }

  async getWorkspace(workspaceId: string): Promise<WorkspaceSummary> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    return this.#workspaceSummary(workspace);
  }

  async listSessions(workspaceId: string): Promise<SessionSummary[]> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    return [...workspace.sessions.values()]
      .map((session) => this.#sessionSummary(session))
      .sort((left, right) => {
        if (left.canPrompt !== right.canPrompt) return left.canPrompt ? -1 : 1;
        if (left.accessMode !== right.accessMode) return left.accessMode === "controller" ? -1 : 1;
        return (left.sessionName || left.sessionId).localeCompare(right.sessionName || right.sessionId);
      });
  }

  async attachBridge(socket: Socket, registration: BridgeRegisterRecord): Promise<BridgeConnection> {
    if (!secretsEqual(registration.secret, this.#bridgeSecret)) throw new Error("Bridge authentication failed");
    const workspace = await this.#loadWorkspace(registration.workspaceId);
    if (registration.workspaceRoot !== workspace.workspace.root) {
      throw new Error("Bridge workspace root did not match registry");
    }
    await this.#reconcileSessions(workspace);

    const existing = workspace.sessions.get(registration.sessionId);
    if (existing?.connection && !existing.connection.closed) {
      throw new Error("Session already has a live TSPi bridge");
    }
    if (registration.accessMode === "controller") {
      const liveController = [...workspace.sessions.values()].find((session) => (
        session.sessionId !== registration.sessionId
        && session.accessMode === "controller"
        && session.connection
        && !session.connection.closed
      ));
      if (liveController) throw new Error("Workspace already has a live controller session");
    }

    const session = existing || this.#createSession(workspace, registration.sessionId, registration.accessMode);
    session.journal.reset();
    session.accessMode = registration.accessMode;
    session.state = "connecting";
    delete session.snapshot;
    delete session.snapshotEventId;
    session.messageCommands.clear();

    const connection = new BridgeConnection(socket, registration, this.#config.commandTimeoutMs);
    session.connection = connection;
    this.#publishState(session);
    connection.onRecord((record) => this.#handleBridgeRecord(session, connection, record));
    connection.onClose(() => this.#handleBridgeClose(session, connection));
    return connection;
  }

  async getMessages(workspaceId: string, sessionId: string): Promise<MessageSnapshot> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const session = workspace.sessions.get(sessionId);
    if (!session) throw new HttpError(404, "session_not_found", "TSPi session was not found");
    if (isLive(session)) {
      if (!session.snapshot || !session.snapshotEventId) {
        throw new HttpError(409, "bridge_connecting", "TSPi bridge has not published a session snapshot yet");
      }
      return {
        sessionId,
        sessionRevision: session.journal.epoch,
        messages: session.snapshot.messages,
        lastEventId: session.snapshotEventId,
      };
    }
    if (!session.persisted) {
      throw new HttpError(409, "session_offline", "Start this TSPi session with --phone before using it");
    }
    const messages = await this.#registry.readPersistedSessionMessages(
      workspace.workspace,
      session.persisted,
    );
    return {
      sessionId,
      sessionRevision: session.journal.epoch,
      messages,
      lastEventId: session.journal.latestId,
    };
  }

  async prompt(workspaceId: string, sessionId: string, input: PromptInput): Promise<void> {
    const session = await this.#connectedSession(workspaceId, sessionId);
    this.#assertRevision(session, input.sessionRevision);
    const existing = session.messageCommands.get(input.clientMessageId);
    if (existing) return existing;
    const connection = session.connection!;
    const command = connection.sendCommand({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      type: "command.prompt",
      workspaceId,
      sessionId,
      instanceEpoch: connection.instanceEpoch,
      sessionGeneration: connection.sessionGeneration,
      clientMessageId: input.clientMessageId,
      message: input.message,
    }).catch((error) => {
      if (error instanceof RuntimeError && (error.code === "command_ambiguous" || error.code === "bridge_disconnected")) {
        session.state = "recovery_required";
        this.#publishState(session);
      }
      throw error;
    });
    session.messageCommands.set(input.clientMessageId, command);
    this.#trimMessageCommands(session.messageCommands);
    return command;
  }

  async abort(workspaceId: string, sessionId: string, input: SessionCommandInput): Promise<void> {
    const session = await this.#connectedSession(workspaceId, sessionId);
    this.#assertRevision(session, input.sessionRevision);
    const connection = session.connection!;
    await connection.sendCommand({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      type: "command.abort",
      workspaceId,
      sessionId,
      instanceEpoch: connection.instanceEpoch,
      sessionGeneration: connection.sessionGeneration,
    });
  }

  async respondToApproval(
    workspaceId: string,
    sessionId: string,
    approvalId: string,
    input: ApprovalInput,
  ): Promise<void> {
    const key = approvalKey(workspaceId, sessionId, approvalId);
    const pending = this.#approvals.get(key);
    if (!pending) {
      throw new HttpError(404, "approval_not_found", "Approval is missing, expired, or already answered");
    }
    if (Date.parse(pending.request.expiresAt) <= Date.now() || pending.connection.closed) {
      this.#approvals.delete(key);
      throw new HttpError(409, "approval_expired", "Approval is no longer valid");
    }
    const session = await this.#connectedSession(workspaceId, sessionId);
    this.#assertRevision(session, input.sessionRevision);
    if (session.connection !== pending.connection
      || pending.sessionRevision !== session.journal.epoch
      || pending.connection.sessionGeneration !== pending.request.sessionGeneration) {
      this.#approvals.delete(key);
      throw new HttpError(409, "approval_stale", "Approval belongs to a stale TSPi session");
    }
    this.#approvals.delete(key);
    await pending.connection.sendCommand({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      type: "approval.respond",
      workspaceId,
      sessionId,
      instanceEpoch: pending.connection.instanceEpoch,
      sessionGeneration: pending.connection.sessionGeneration,
      approvalId,
      approved: input.approved,
    });
  }

  async journal(workspaceId: string, sessionId: string): Promise<EventJournal> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const session = workspace.sessions.get(sessionId);
    if (!session) throw new HttpError(404, "session_not_found", "TSPi session was not found");
    return session.journal;
  }

  close(): void {
    clearInterval(this.#staleTimer);
    for (const workspace of this.#records.values()) {
      for (const session of workspace.sessions.values()) session.connection?.close();
    }
    this.#approvals.clear();
  }

  #handleBridgeRecord(
    session: SessionRecord,
    connection: BridgeConnection,
    bridgeRecord: Exclude<BridgeClientRecord, BridgeRegisterRecord | { type: "command.ack" }>,
  ): void {
    if (session.connection !== connection) return;
    const identity = {
      instanceEpoch: connection.instanceEpoch,
      sessionGeneration: connection.sessionGeneration,
    };
    if (bridgeRecord.type === "bridge.heartbeat") return;
    if (bridgeRecord.type === "session.snapshot") {
      if (bridgeRecord.snapshot.sessionId !== session.sessionId) {
        throw new Error("Bridge snapshot sessionId did not match registration");
      }
      const snapshot = {
        ...bridgeRecord.snapshot,
        messages: projectSnapshotMessages(bridgeRecord.snapshot.messages),
      };
      session.snapshot = snapshot;
      session.state = snapshot.isStreaming ? "running" : "idle";
      session.snapshotEventId = session.journal.publish(
        "session.snapshot",
        {
          ...snapshot,
          messages: [...snapshot.messages],
          accessMode: session.accessMode,
          historyAvailable: Boolean(session.persisted),
          historyOnly: false,
          canPrompt: true,
        },
        identity,
      ).id;
      this.#publishState(session);
      return;
    }
    if (bridgeRecord.type === "approval.request") {
      this.#acceptApproval(session, connection, bridgeRecord);
      session.journal.publish("approval.request", {
        id: bridgeRecord.approvalId,
        method: "confirm",
        message: bridgeRecord.preview,
        preview: bridgeRecord.preview,
        toolName: bridgeRecord.toolName,
        turnId: bridgeRecord.turnId,
        toolCallId: bridgeRecord.toolCallId,
        expiresAt: bridgeRecord.expiresAt,
      }, identity);
      return;
    }
    if (bridgeRecord.eventType === "agent_start") {
      session.state = "running";
      if (session.snapshot) session.snapshot.isStreaming = true;
    }
    if (bridgeRecord.eventType === "agent_settled") {
      session.state = "idle";
      if (session.snapshot) session.snapshot.isStreaming = false;
    }
    if (bridgeRecord.eventType === "message_end" && session.snapshot) {
      const message = messageFromEndEvent(bridgeRecord.payload);
      if (message !== undefined) {
        session.snapshot.messages = appendProjectedMessage(session.snapshot.messages, message);
      }
    }
    const event = session.journal.publish(bridgeRecord.eventType, bridgeRecord.payload, identity);
    if (bridgeRecord.eventType === "message_end" && session.snapshot) session.snapshotEventId = event.id;
    if (bridgeRecord.eventType === "agent_start" || bridgeRecord.eventType === "agent_settled") {
      this.#publishState(session);
    }
  }

  #acceptApproval(
    session: SessionRecord,
    connection: BridgeConnection,
    request: BridgeApprovalRequestRecord,
  ): void {
    if (session.accessMode !== "controller") {
      throw new Error("Observer session attempted to request a write approval");
    }
    const expiresAt = Date.parse(request.expiresAt);
    if (expiresAt <= Date.now() || expiresAt > Date.now() + 5 * 60_000) {
      throw new Error("Bridge approval expiry is outside the allowed window");
    }
    const key = approvalKey(connection.workspaceId, connection.sessionId, request.approvalId);
    if (this.#approvals.has(key)) throw new Error("Bridge approval id was reused");
    this.#approvals.set(key, { connection, request, sessionRevision: session.journal.epoch });
  }

  #handleBridgeClose(session: SessionRecord, connection: BridgeConnection): void {
    if (session.connection !== connection) return;
    delete session.connection;
    delete session.snapshot;
    delete session.snapshotEventId;
    session.messageCommands.clear();
    session.state = session.state === "running" ? "recovery_required" : "offline";
    for (const [key, pending] of this.#approvals) {
      if (pending.connection === connection) this.#approvals.delete(key);
    }
    this.#publishState(session);
  }

  async #connectedSession(workspaceId: string, sessionId: string): Promise<SessionRecord> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const session = workspace.sessions.get(sessionId);
    if (!session) throw new HttpError(404, "session_not_found", "TSPi session was not found");
    if (!session.connection || session.connection.closed) {
      throw new HttpError(409, "session_offline", "Start this TSPi session with --phone before using it");
    }
    return session;
  }

  #assertRevision(session: SessionRecord, revision: string): void {
    if (revision !== session.journal.epoch) {
      throw new HttpError(409, "session_resync_required", "TSPi session changed; refresh before sending a command");
    }
  }

  #ensureWorkspace(workspace: RegisteredWorkspace): WorkspaceRecord {
    const existing = this.#records.get(workspace.id);
    if (existing?.workspace.root === workspace.root) return existing;
    if (existing) this.#discardWorkspace(workspace.id);
    const created: WorkspaceRecord = { workspace, sessions: new Map() };
    this.#records.set(workspace.id, created);
    return created;
  }

  async #loadWorkspace(workspaceId: string): Promise<WorkspaceRecord> {
    try {
      return this.#ensureWorkspace(await this.#registry.get(workspaceId));
    } catch (error) {
      if (error instanceof HttpError && error.code === "workspace_not_found") {
        this.#discardWorkspace(workspaceId);
      }
      throw error;
    }
  }

  async #reconcileSessions(workspace: WorkspaceRecord): Promise<void> {
    const persisted = await this.#registry.listPersistedSessionIds(workspace.workspace);
    for (const diskSession of persisted.sessions.values()) {
      const existing = workspace.sessions.get(diskSession.id);
      if (existing) {
        existing.persisted = diskSession;
      } else {
        this.#createSession(workspace, diskSession.id, "observer", diskSession);
      }
    }
    if (!persisted.complete) return;
    for (const [sessionId, session] of workspace.sessions) {
      if (persisted.ids.has(sessionId)) continue;
      delete session.persisted;
      if (!isLive(session)) this.#discardSession(workspace, sessionId);
    }
  }

  #discardWorkspace(workspaceId: string): void {
    const workspace = this.#records.get(workspaceId);
    if (!workspace) return;
    this.#records.delete(workspaceId);
    for (const sessionId of [...workspace.sessions.keys()]) this.#discardSession(workspace, sessionId);
  }

  #discardSession(workspace: WorkspaceRecord, sessionId: string): void {
    const session = workspace.sessions.get(sessionId);
    if (!session) return;
    workspace.sessions.delete(sessionId);
    const connection = session.connection;
    if (connection) {
      for (const [key, pending] of this.#approvals) {
        if (pending.connection === connection) this.#approvals.delete(key);
      }
      connection.close();
    }
    session.messageCommands.clear();
  }

  #createSession(
    workspace: WorkspaceRecord,
    sessionId: string,
    accessMode: "controller" | "observer",
    persisted?: PersistedSession,
  ): SessionRecord {
    const session: SessionRecord = {
      sessionId,
      journal: new EventJournal(
        workspace.workspace.id,
        sessionId,
        this.#config.eventJournalSize,
        this.#config.eventJournalMaxBytes,
      ),
      state: "offline",
      accessMode,
      messageCommands: new Map(),
    };
    if (persisted) session.persisted = persisted;
    workspace.sessions.set(sessionId, session);
    return session;
  }

  #workspaceSummary(workspace: WorkspaceRecord): WorkspaceSummary {
    const sessions = [...workspace.sessions.values()];
    const live = sessions.filter((session) => session.connection && !session.connection.closed);
    const state = aggregateState(sessions.map((session) => session.state));
    return {
      id: workspace.workspace.id,
      name: workspace.workspace.name,
      runtimeState: state,
      isStreaming: sessions.some((session) => session.state === "running"),
      liveSessionCount: live.length,
      sessionCount: sessions.length,
    };
  }

  #sessionSummary(session: SessionRecord): SessionSummary {
    const live = isLive(session);
    const historyAvailable = Boolean(session.persisted);
    const summary: SessionSummary = {
      sessionId: session.sessionId,
      sessionRevision: session.journal.epoch,
      runtimeState: session.state,
      isStreaming: session.state === "running",
      accessMode: session.accessMode,
      historyAvailable,
      historyOnly: session.state === "offline" && !live && historyAvailable,
      canPrompt: live,
    };
    if (session.snapshot?.sessionName) summary.sessionName = session.snapshot.sessionName;
    if (session.snapshot?.model) summary.model = session.snapshot.model;
    return summary;
  }

  #publishState(session: SessionRecord): void {
    const connection = session.connection;
    session.journal.publish("session_state", {
      state: session.state,
      sessionId: session.sessionId,
      sessionName: session.snapshot?.sessionName,
      model: session.snapshot?.model,
      isStreaming: session.state === "running",
      accessMode: session.accessMode,
      historyAvailable: Boolean(session.persisted),
      historyOnly: session.state === "offline" && !isLive(session) && Boolean(session.persisted),
      canPrompt: isLive(session),
    }, connection ? {
      instanceEpoch: connection.instanceEpoch,
      sessionGeneration: connection.sessionGeneration,
    } : undefined);
  }

  #closeStaleConnections(): void {
    const cutoff = Date.now() - this.#config.bridgeHeartbeatTimeoutMs;
    for (const workspace of this.#records.values()) {
      for (const session of workspace.sessions.values()) {
        if (session.connection && session.connection.lastSeenAt < cutoff) session.connection.close();
      }
    }
    for (const [key, pending] of this.#approvals) {
      if (Date.parse(pending.request.expiresAt) <= Date.now()) this.#approvals.delete(key);
    }
  }

  #trimMessageCommands(commands: Map<string, Promise<void>>): void {
    while (commands.size > 1_000) {
      const first = commands.keys().next().value as string | undefined;
      if (!first) break;
      commands.delete(first);
    }
  }
}

function approvalKey(workspaceId: string, sessionId: string, approvalId: string): string {
  return `${workspaceId}\u0000${sessionId}\u0000${approvalId}`;
}

function aggregateState(states: RuntimeState[]): RuntimeState {
  if (states.includes("running")) return "running";
  if (states.includes("idle")) return "idle";
  if (states.includes("connecting")) return "connecting";
  if (states.includes("recovery_required")) return "recovery_required";
  return "offline";
}

function messageFromEndEvent(payload: unknown): unknown | undefined {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return undefined;
  return (payload as Record<string, unknown>).message;
}

function isLive(session: SessionRecord): boolean {
  return Boolean(session.connection && !session.connection.closed);
}
