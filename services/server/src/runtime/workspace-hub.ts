import { createHash, randomUUID } from "node:crypto";
import type { Socket } from "node:net";
import type { ServerConfig } from "../config.js";
import { EventJournal } from "../event-journal.js";
import { HttpError, RuntimeError } from "../errors.js";
import {
  ManagementStore,
  type ManagedSession,
  type ManagedWorkspace,
  type NewSessionMetadata,
} from "../management-store.js";
import { appendProjectedMessage, projectSnapshotMessagePage } from "../message-projection.js";
import { secretsEqual } from "../security.js";
import type {
  AbortInput,
  ActivateInput,
  ApprovalInput,
  CreateSessionInput,
  CreateWorkspaceInput,
  LifecycleInput,
  LifecycleState,
  MessagePage,
  MessagePageRequest,
  MessageSnapshot,
  PromptInput,
  PurgeInput,
  RenameInput,
  RuntimeState,
  SessionCapability,
  SessionActivation,
  SessionAccessMode,
  SessionRuntimeSnapshot,
  SessionSnapshot,
  SessionSummary,
  TimelinePageRequest,
  TimelineSnapshot,
  WorkspaceCreationResult,
  WorkspaceDeletionPreflight,
  WorkspaceSummary,
} from "../types.js";
import {
  WorkspaceRegistry,
  type PersistedSession,
  type RegisteredWorkspace,
} from "../workspace-registry.js";
import { WorkerSupervisor, type WorkerExit } from "./worker-supervisor.js";
import type { LifecycleGuard, LifecyclePreflight } from "./lifecycle-client.js";
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
  workspaceId: string;
  sessionId: string;
  journal: EventJournal;
  state: RuntimeState;
  accessMode: "controller" | "observer";
  persisted?: PersistedSession;
  connection?: BridgeConnection;
  snapshot?: SessionSnapshot;
  runtime?: SessionRuntimeSnapshot;
  snapshotEventId?: string;
  activeAgentRunId?: string;
  messageCommands: Map<string, { digest: string; result: Promise<void> }>;
  pendingPrompts: number;
  unstartedPrompts: Set<string>;
  observedPrompts: Set<string>;
  activating?: boolean;
  switching?: boolean;
}

interface PendingActivation {
  sessionId: string;
  input: ActivateInput;
  result: Promise<SessionSummary>;
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
  readonly #management: ManagementStore;
  readonly #workers: WorkerSupervisor;
  readonly #guardedWorkspaces = new Set<string>();
  readonly #records = new Map<string, WorkspaceRecord>();
  readonly #approvals = new Map<string, PendingApproval>();
  readonly #bridgeWaiters = new Map<string, Set<() => void>>();
  readonly #activations = new Map<string, PendingActivation>();
  readonly #activationRequests = new Map<string, PendingActivation>();
  readonly #staleTimer: NodeJS.Timeout;
  #mutationTail: Promise<void> = Promise.resolve();
  #closing = false;

  constructor(
    config: ServerConfig,
    bridgeSecret: string,
    management: ManagementStore,
    workers = new WorkerSupervisor(
      config.tspiPath,
      config.shutdownTimeoutMs,
      config.bridgeSocketPath,
      config.bridgeSecretPath,
    ),
    registry = new WorkspaceRegistry(config.workspaceRoot),
  ) {
    this.#config = config;
    this.#bridgeSecret = bridgeSecret;
    this.#management = management;
    this.#workers = workers;
    workers.onRuntimeError = (request, error) => {
      const session = this.#records.get(request.workspaceId)?.sessions.get(request.sessionId);
      if (session) session.journal.publish("runtime.error", { code: error.code });
    };
    this.#registry = registry;
    this.#staleTimer = setInterval(() => this.#closeStaleConnections(), 10_000);
    this.#staleTimer.unref();
  }

  async listWorkspaces(lifecycleState: LifecycleState = "active"): Promise<WorkspaceSummary[]> {
    const workspaces = await this.#registry.list();
    const registeredIds = new Set(workspaces.map((workspace) => workspace.id));
    for (const workspaceId of this.#records.keys()) {
      if (!registeredIds.has(workspaceId)) this.#discardWorkspace(workspaceId);
    }
    const summaries: WorkspaceSummary[] = [];
    for (const registered of workspaces) {
      const metadata = this.#management.workspace(registered.id);
      if ((metadata?.lifecycleState ?? "active") !== lifecycleState) continue;
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

  async listSessions(
    workspaceId: string,
    lifecycleState: LifecycleState = "active",
  ): Promise<SessionSummary[]> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    return [...workspace.sessions.values()]
      .filter((session) => (
        (this.#management.session(workspaceId, session.sessionId)?.lifecycleState ?? "active")
        === lifecycleState
      ))
      .map((session) => this.#sessionSummary(session))
      .sort((left, right) => {
        if (left.canPrompt !== right.canPrompt) return left.canPrompt ? -1 : 1;
        if (left.accessMode !== right.accessMode) return left.accessMode === "controller" ? -1 : 1;
        return (left.sessionName || left.sessionId).localeCompare(right.sessionName || right.sessionId);
      });
  }

  async createWorkspace(input: CreateWorkspaceInput): Promise<WorkspaceCreationResult> {
    return this.#serializeMutation(async () => {
      const registered = await this.#registry.list();
      const workspaceId = nextWorkspaceId([
        ...registered.map((workspace) => workspace.id),
        ...this.#management.workspaceIds(),
      ]);
      const sessionId = "session_1";
      const workspace = await this.#registry.create(workspaceId);
      try {
        await this.#management.createWorkspace(workspaceId, input.name, sessionId, {
          accessMode: "controller",
          name: input.name,
        });
      } catch (error) {
        const quarantine = await this.#registry.quarantineWorkspace(workspace);
        await this.#registry.deleteQuarantine(quarantine);
        throw error;
      }
      const record = this.#ensureWorkspace(workspace);
      await this.#reconcileSessions(record);
      const session = record.sessions.get(sessionId);
      if (!session) throw new Error("Created workspace session was not reconciled");
      return {
        workspace: this.#workspaceSummary(record),
        session: this.#sessionSummary(session),
      };
    });
  }

  async createSession(workspaceId: string, input: CreateSessionInput): Promise<SessionSummary> {
    return this.#serializeMutation(async () => {
      const workspace = await this.#loadWorkspace(workspaceId);
      const workspaceMetadata = this.#management.workspace(workspaceId);
      if (workspaceMetadata?.lifecycleState !== undefined
        && workspaceMetadata.lifecycleState !== "active") {
        throw new HttpError(409, "workspace_not_active", "Restore the workspace before creating a session");
      }
      const persisted = await this.#registry.listPersistedSessionIds(workspace.workspace);
      const sessionId = nextSessionId([
        ...persisted.ids,
        ...this.#management.sessionIds(workspaceId),
        ...workspace.sessions.keys(),
      ]);
      const metadata: NewSessionMetadata = {
        accessMode: input.accessMode,
        ...(input.name ? { name: input.name } : {}),
        ...(input.model ? { model: input.model } : {}),
      };
      await this.#management.createSession(
        workspaceId,
        workspaceMetadata?.name ?? workspace.workspace.name,
        sessionId,
        metadata,
      );
      await this.#reconcileSessions(workspace);
      const created = workspace.sessions.get(sessionId);
      if (!created) throw new Error("Created session was not reconciled");
      return this.#sessionSummary(created);
    });
  }

  async renameWorkspace(workspaceId: string, input: RenameInput): Promise<WorkspaceSummary> {
    return this.#serializeMutation(async () => {
      const workspace = await this.#loadWorkspace(workspaceId);
      await this.#management.renameWorkspace(
        workspaceId,
        workspace.workspace.name,
        input.managementRevision,
        input.name,
      );
      return this.#workspaceSummary(workspace);
    });
  }

  async renameSession(
    workspaceId: string,
    sessionId: string,
    input: RenameInput,
  ): Promise<SessionSummary> {
    return this.#serializeMutation(async () => {
      const { workspace, session } = await this.#managedSession(workspaceId, sessionId);
      await this.#management.renameSession(
        workspaceId,
        this.#workspaceName(workspace),
        sessionId,
        input.managementRevision,
        input.name,
        this.#sessionDefaults(session),
      );
      return this.#sessionSummary(session);
    });
  }

  async archiveWorkspace(workspaceId: string, input: LifecycleInput): Promise<WorkspaceSummary> {
    return this.#serializeMutation(async () => {
      const workspace = await this.#loadWorkspace(workspaceId);
      this.#assertWorkspaceManagementRevision(
        workspaceId,
        input.managementRevision,
      );
      await this.#stopIdleOwnedWorkers(workspace);
      if (this.#blockingWorkerCount(workspace) > 0) {
        throw new HttpError(409, "workspace_has_active_workers", "Stop active TSPi sessions before archiving the workspace");
      }
      await this.#management.transitionWorkspace(
        workspaceId,
        workspace.workspace.name,
        input.managementRevision,
        "archived",
      );
      return this.#workspaceSummary(workspace);
    });
  }

  async restoreWorkspace(workspaceId: string, input: LifecycleInput): Promise<WorkspaceSummary> {
    return this.#serializeMutation(async () => {
      const workspace = await this.#loadWorkspace(workspaceId);
      await this.#management.transitionWorkspace(
        workspaceId,
        workspace.workspace.name,
        input.managementRevision,
        "active",
      );
      return this.#workspaceSummary(workspace);
    });
  }

  async workspaceDeletionPreflight(workspaceId: string): Promise<WorkspaceDeletionPreflight> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const metadata = this.#management.workspace(workspaceId);
    const scientific = await this.#workers.inspect(workspaceId, workspace.workspace.root);
    return this.#deletionPreflight(workspace, scientific, metadata);
  }

  #deletionPreflight(
    workspace: WorkspaceRecord,
    scientific: LifecyclePreflight,
    metadata = this.#management.workspace(workspace.workspace.id),
  ): WorkspaceDeletionPreflight {
    const workspaceId = workspace.workspace.id;
    const knownController = [...workspace.sessions.values()].some((session) => (
      session.accessMode === "controller"
      && (isLive(session) || this.#workers.owns(workspaceId, session.sessionId))
    ));
    const activeWorkers = this.#blockingWorkerCount(workspace)
      + (scientific.rootAgentActive && !knownController ? 1 : 0)
      + (scientific.sessionWritersActive && ![...workspace.sessions.values()].some(isLive) ? 1 : 0);
    const pendingApprovals = this.#workspaceApprovalCount(workspaceId);
    return {
      workspaceId,
      managementRevision: metadata?.managementRevision ?? "unmanaged",
      activeWorkers,
      remoteCalculations: scientific.remoteCalculations,
      pendingApprovals,
      unresolvedRemoteEffects: scientific.unresolvedRemoteEffects,
      canDelete: activeWorkers === 0
        && scientific.remoteCalculations === 0
        && pendingApprovals === 0
        && scientific.unresolvedRemoteEffects === 0,
    };
  }

  async trashWorkspace(workspaceId: string, input: LifecycleInput): Promise<WorkspaceSummary> {
    return this.#serializeMutation(async () => {
      const workspace = await this.#loadWorkspace(workspaceId);
      this.#assertWorkspaceManagementRevision(
        workspaceId,
        input.managementRevision,
      );
      await this.#stopIdleOwnedWorkers(workspace);
      return this.#withLifecycleGuard(workspace, async (guard) => {
        const preflight = this.#deletionPreflight(workspace, guard);
        if (preflight.managementRevision !== input.managementRevision) {
          throw new HttpError(409, "workspace_management_changed", "Workspace changed; refresh and try again");
        }
        if (!preflight.canDelete) {
          throw new HttpError(409, "workspace_delete_blocked", "Workspace still has active or unresolved resources");
        }
        guard.assertHeld();
        await this.#management.transitionWorkspace(
          workspaceId,
          workspace.workspace.name,
          input.managementRevision,
          "trashed",
        );
        return this.#workspaceSummary(workspace);
      });
    });
  }

  async purgeWorkspace(workspaceId: string, input: PurgeInput): Promise<void> {
    await this.#serializeMutation(async () => {
      if (input.confirmation !== workspaceId) {
        throw new HttpError(400, "purge_confirmation_mismatch", "Permanent deletion confirmation does not match the workspace id");
      }
      const workspace = await this.#loadWorkspace(workspaceId);
      const metadata = this.#management.workspace(workspaceId);
      if (!metadata || metadata.lifecycleState !== "trashed") {
        throw new HttpError(409, "workspace_not_trashed", "Move the workspace to Recently Deleted before purging it");
      }
      await this.#withLifecycleGuard(workspace, async (guard) => {
        const preflight = this.#deletionPreflight(workspace, guard);
        if (preflight.managementRevision !== input.managementRevision || !preflight.canDelete) {
          throw new HttpError(409, "workspace_delete_blocked", "Workspace changed or still has active resources");
        }
        guard.assertHeld();
        const quarantine = await this.#registry.quarantineWorkspace(workspace.workspace);
        let managementPurged = false;
        try {
          guard.assertHeld();
          await this.#management.purgeWorkspace(workspaceId, input.managementRevision);
          managementPurged = true;
          guard.assertHeld();
          await this.#registry.deleteQuarantine(quarantine);
        } catch (error) {
          const recoveryErrors: unknown[] = [];
          try {
            await this.#registry.restoreQuarantine(quarantine);
          } catch (recoveryError) {
            recoveryErrors.push(recoveryError);
          }
          if (managementPurged) {
            try {
              await this.#management.restorePurgedWorkspace(workspaceId, metadata);
            } catch (recoveryError) {
              recoveryErrors.push(recoveryError);
            }
          }
          if (recoveryErrors.length > 0) {
            throw new RuntimeError(
              "purge_recovery_failed",
              "Permanent project deletion failed and automatic recovery was incomplete; inspect Host state before retrying",
            );
          }
          throw error;
        }
        this.#discardWorkspace(workspaceId);
      });
    });
  }

  async archiveSession(
    workspaceId: string,
    sessionId: string,
    input: LifecycleInput,
  ): Promise<SessionSummary> {
    return this.#transitionSession(workspaceId, sessionId, input, "archived");
  }

  async restoreSession(
    workspaceId: string,
    sessionId: string,
    input: LifecycleInput,
  ): Promise<SessionSummary> {
    return this.#transitionSession(workspaceId, sessionId, input, "active", false);
  }

  async trashSession(
    workspaceId: string,
    sessionId: string,
    input: LifecycleInput,
  ): Promise<SessionSummary> {
    return this.#transitionSession(workspaceId, sessionId, input, "trashed");
  }

  async purgeSession(
    workspaceId: string,
    sessionId: string,
    input: PurgeInput,
  ): Promise<void> {
    await this.#serializeMutation(async () => {
      if (input.confirmation !== sessionId) {
        throw new HttpError(400, "purge_confirmation_mismatch", "Permanent deletion confirmation does not match the session id");
      }
      const { workspace, session } = await this.#managedSession(workspaceId, sessionId);
      const metadata = this.#management.session(workspaceId, sessionId);
      if (!metadata || metadata.lifecycleState !== "trashed") {
        throw new HttpError(409, "session_not_trashed", "Move the session to Recently Deleted before purging it");
      }
      this.#assertSessionCanHide(workspaceId, session);
      if (metadata.managementRevision !== input.managementRevision) {
        throw new HttpError(409, "session_management_changed", "Session changed; refresh and try again");
      }
      const workspaceSnapshot = this.#management.workspace(workspaceId);
      if (!workspaceSnapshot) {
        throw new HttpError(409, "workspace_management_changed", "Workspace changed; refresh and try again");
      }
      const purge = async (guard?: LifecycleGuard): Promise<void> => {
        guard?.assertHeld();
        const quarantine = session.persisted
          ? await this.#registry.quarantineSession(workspace.workspace, session.persisted)
          : undefined;
        let managementPurged = false;
        try {
          guard?.assertHeld();
          await this.#management.purgeSession(workspaceId, sessionId, input.managementRevision);
          managementPurged = true;
          guard?.assertHeld();
          if (quarantine) await this.#registry.deleteQuarantine(quarantine);
        } catch (error) {
          const recoveryErrors: unknown[] = [];
          if (quarantine) {
            try {
              await this.#registry.restoreQuarantine(quarantine);
            } catch (recoveryError) {
              recoveryErrors.push(recoveryError);
            }
          }
          if (managementPurged) {
            try {
              await this.#management.restorePurgedSession(
                workspaceId,
                sessionId,
                workspaceSnapshot,
              );
            } catch (recoveryError) {
              recoveryErrors.push(recoveryError);
            }
          }
          if (recoveryErrors.length > 0) {
            throw new RuntimeError(
              "purge_recovery_failed",
              "Permanent conversation deletion failed and automatic recovery was incomplete; inspect Host state before retrying",
            );
          }
          throw error;
        }
        this.#discardSession(workspace, sessionId);
      };
      if (session.persisted) await this.#withLifecycleGuard(workspace, purge);
      else await purge();
    });
  }

  async activateSession(
    workspaceId: string,
    sessionId: string,
    input: ActivateInput,
  ): Promise<SessionSummary> {
    const admitted = await this.#serializeMutation(async () => {
      if (this.#closing) throw new HttpError(503, "host_stopping", "TSPi Host is stopping");
      const requestKey = input.requestId ? `${workspaceId}\u0000${sessionId}\u0000${input.requestId}` : undefined;
      const previous = requestKey ? this.#activationRequests.get(requestKey) : undefined;
      if (previous) {
        if (!sameActivation(previous.input, input)) {
          throw new HttpError(409, "activation_id_conflict", "Activation identity was reused with different parameters");
        }
        return { result: previous.result.then(async () => {
          const { session } = await this.#managedSession(workspaceId, sessionId);
          return this.#sessionSummary(session);
        }) };
      }
      const pending = this.#activations.get(workspaceId);
      if (pending) {
        if (pending.sessionId === sessionId && sameActivation(pending.input, input)) return pending;
        throw new HttpError(409, "workspace_activating", "Another conversation is starting in this workspace");
      }
      const { workspace, session } = await this.#managedSession(workspaceId, sessionId);
      const workspaceMetadata = this.#management.workspace(workspaceId);
      const sessionMetadata = this.#management.session(workspaceId, sessionId);
      if (workspaceMetadata?.lifecycleState !== undefined && workspaceMetadata.lifecycleState !== "active") {
        throw new HttpError(409, "workspace_not_active", "Restore the workspace before starting a session");
      }
      if (sessionMetadata?.lifecycleState !== undefined && sessionMetadata.lifecycleState !== "active") {
        throw new HttpError(409, "session_not_active", "Restore the session before starting it");
      }
      if (sessionMetadata && sessionMetadata.managementRevision !== input.managementRevision) {
        throw new HttpError(409, "session_management_changed", "Session changed; refresh and try again");
      }
      if (!sessionMetadata && input.managementRevision !== "unmanaged") {
        throw new HttpError(409, "session_management_changed", "Session changed; refresh and try again");
      }
      const accessMode = input.accessMode ?? sessionMetadata?.accessMode ?? session.accessMode;
      if (requestKey && this.#activationRequests.size >= 1_000) {
        throw new HttpError(409, "activation_capacity_exceeded", "Activation receipt capacity reached; schedule Host maintenance before more starts");
      }
      if (isLive(session) && accessMode === session.accessMode) {
        if (!canPrompt(session)) {
          throw new HttpError(409, promptProblem(session) ?? "session_not_ready", "This conversation is not ready; refresh its runtime state");
        }
        const reused: PendingActivation = { sessionId, input: cloneActivation(input), result: Promise.resolve(this.#sessionSummary(session)) };
        if (requestKey) this.#activationRequests.set(requestKey, reused);
        return reused;
      }
      if (session.state === "recovery_required" || (!isLive(session) && this.#workers.owns(workspaceId, sessionId))) {
        throw new HttpError(409, "session_recovery_required", "Inspect the existing runtime before starting another one");
      }
      const controller = this.#controller(workspace);
      if (isLive(session) && accessMode === "controller" && controller && controller !== session) {
        throw new HttpError(409, "controller_session_active", "Open the existing Controller before changing this assistant's mode");
      }
      const source = isLive(session) ? session : (accessMode === "controller" ? controller : undefined);
      if (source) {
        const conflict = this.#runtimeConflict(source);
        if (!conflict.switchable) {
          throw new HttpError(409, conflict.owner === "external" ? "external_controller" : "controller_session_active",
            "The current runtime cannot be switched; open its conversation instead");
        }
        if (input.switchFrom?.sessionId !== source.sessionId || input.switchFrom.sessionRevision !== source.journal.epoch) {
          throw new HttpError(409, "session_switch_required", "Confirm switching the current idle conversation with its latest revision");
        }
        source.switching = true;
        this.#publishState(source);
      } else if (input.switchFrom) {
        throw new HttpError(409, "session_switch_stale", "The runtime to switch changed; refresh before continuing");
      }
      session.activating = true;
      const result = this.#activateRuntime(workspace, session, input, accessMode, source)
        .finally(() => {
          delete session.activating;
          if (source) delete source.switching;
          this.#activations.delete(workspaceId);
          this.#publishState(session);
          if (source && source !== session) this.#publishState(source);
        }).then(() => this.#sessionSummary(session));
      const operation: PendingActivation = { sessionId, input: cloneActivation(input), result };
      this.#activations.set(workspaceId, operation);
      if (requestKey) this.#activationRequests.set(requestKey, operation);
      return operation;
    });
    return admitted.result;
  }

  async #activateRuntime(
    workspace: WorkspaceRecord,
    session: SessionRecord,
    input: ActivateInput,
    accessMode: SessionAccessMode,
    source?: SessionRecord,
  ): Promise<SessionSummary> {
    const workspaceId = session.workspaceId;
    const sessionId = session.sessionId;
    const key = bridgeWaiterKey(workspaceId, sessionId);
    const ready = this.#bridgeWaiter(key);
    const launchId = randomUUID();
    let timer: NodeJS.Timeout | undefined;
    let targetStartupAttempted = false;
    try {
      await this.#workers.checkCompatibility();
      if (source) await this.#stopIdleWorker(source);
      targetStartupAttempted = true;
      session.state = "connecting";
      this.#publishState(session);
      const metadata = this.#management.session(workspaceId, sessionId) ?? this.#sessionDefaults(session);
      const launch = await this.#workers.start({
        workspaceId, sessionId, accessMode, launchId,
        ...(metadata.name ? { name: metadata.name } : {}),
        ...(metadata.model ? { model: metadata.model } : {}),
      });
      const outcome = await Promise.race([
        ready.promise.then(() => ({ ready: true as const })),
        launch.exit.then((exit) => ({ exit })),
        new Promise<{ timeout: true }>((resolve) => { timer = setTimeout(() => resolve({ timeout: true }), 15_000); }),
      ]);
      if ("exit" in outcome) {
        const error = workerStartError(outcome.exit);
        console.warn(JSON.stringify({ event: "worker_start_failed", workspaceId, code: error.code }));
        throw error;
      }
      if ("timeout" in outcome) throw new HttpError(504, "worker_start_timeout", "TSPi did not publish a ready session in time");
      if (this.#closing || !isLive(session) || !session.snapshot || session.accessMode !== accessMode) {
        throw new HttpError(409, "worker_start_interrupted", "TSPi startup was interrupted before the session became ready");
      }
      const problem = promptProblem(session);
      if (problem) throw new HttpError(409, problem, "The selected model is not configured for this TSPi runtime");
      await this.#serializeMutation(async () => {
        if (this.#closing || !isLive(session)) throw new HttpError(409, "worker_start_interrupted", "TSPi disconnected during activation");
        await this.#management.rememberSessionActivation(workspaceId, this.#workspaceName(workspace),
          sessionId, input.managementRevision, { ...metadata, accessMode });
        // This is the activation commit point. A subsequent exit is a runtime
        // state change, not a reason to roll back a successfully saved preference.
        delete session.activating;
        this.#publishState(session);
      });
      return this.#sessionSummary(session);
    } catch (error) {
      // A failed preflight has not touched the old runtime. Stop failures are
      // attributed to their source by #stopIdleWorker, not to this target.
      if (!targetStartupAttempted) throw error;
      try {
        if (this.#workers.request(workspaceId, sessionId)?.launchId === launchId) {
          await this.#workers.stop(workspaceId, sessionId);
          session.connection?.close();
        }
        session.state = this.#workers.owns(workspaceId, sessionId) ? "recovery_required" : "offline";
      } catch {
        session.state = "recovery_required";
        throw new HttpError(409, "worker_cleanup_uncertain", "TSPi startup failed and process cleanup could not be confirmed");
      }
      throw error;
    } finally {
      if (timer) clearTimeout(timer);
      this.#cancelBridgeWaiter(key, ready.resolve);
    }
  }

  async attachBridge(socket: Socket, registration: BridgeRegisterRecord): Promise<BridgeConnection> {
    if (!secretsEqual(registration.secret, this.#bridgeSecret)) throw new Error("Bridge authentication failed");
    const workspace = await this.#loadWorkspace(registration.workspaceId);
    if (registration.workspaceRoot !== workspace.workspace.root) {
      throw new Error("Bridge workspace root did not match registry");
    }
    await this.#reconcileSessions(workspace);
    await this.#workers.verifyWriter(registration.workspaceId, registration.workspaceRoot,
      registration.sessionId, registration.accessMode, registration.pid);

    const workspaceMetadata = this.#management.workspace(registration.workspaceId);
    const sessionMetadata = this.#management.session(registration.workspaceId, registration.sessionId);
    if (workspaceMetadata && workspaceMetadata.lifecycleState !== "active") {
      throw new Error("Bridge cannot attach to an inactive workspace");
    }
    if (sessionMetadata && sessionMetadata.lifecycleState !== "active") {
      throw new Error("Bridge cannot attach to an inactive session");
    }
    const owned = this.#workers.request(registration.workspaceId, registration.sessionId);
    if (owned) {
      if (owned.launchId !== registration.launchId || owned.accessMode !== registration.accessMode) {
        throw new Error("Bridge did not match the admitted TSPi launch");
      }
    } else if (registration.launchId) {
      throw new Error("Bridge belongs to an unknown TSPi launch; runtime recovery is required");
    }

    const existing = workspace.sessions.get(registration.sessionId);
    if ((existing?.activating && !owned) || existing?.switching) {
      throw new Error("Conversation runtime admission is already reserved");
    }
    if (this.#guardedWorkspaces.has(registration.workspaceId)) {
      throw new Error("Workspace lifecycle operation is in progress");
    }
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
    delete session.activeAgentRunId;
    session.messageCommands.clear();
    session.unstartedPrompts.clear();
    session.observedPrompts.clear();

    const connection = new BridgeConnection(socket, registration, this.#config.commandTimeoutMs);
    session.connection = connection;
    this.#publishState(session);
    connection.onRecord((record) => this.#handleBridgeRecord(session, connection, record));
    connection.onClose(() => this.#handleBridgeClose(session, connection));
    return connection;
  }

  async getMessages(
    workspaceId: string,
    sessionId: string,
    request: MessagePageRequest,
  ): Promise<MessageSnapshot> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const session = workspace.sessions.get(sessionId);
    if (!session) throw new HttpError(404, "session_not_found", "TSPi session was not found");
    if (isLive(session) && request.before === undefined && request.after === undefined && request.edge === undefined) {
      if (!session.snapshot || !session.snapshotEventId) {
        throw new HttpError(409, "bridge_connecting", "TSPi bridge has not published a session snapshot yet");
      }
      return {
        sessionId,
        sessionRevision: session.journal.epoch,
        activeAgentRunId: session.activeAgentRunId ?? null,
        ...messagePageFromSnapshot(session.snapshot, request.limit),
        lastEventId: session.snapshotEventId,
      };
    }
    if (!session.persisted) {
      if (request.before !== undefined) {
        throw new HttpError(
          409,
          "session_history_unavailable",
          "Earlier session history is not available on disk",
        );
      }
      throw new HttpError(409, "session_offline", "Start this TSPi session with --phone before using it");
    }
    const page = await this.#registry.readPersistedSessionMessages(
      workspace.workspace,
      session.persisted,
      request,
    );
    return {
      sessionId,
      sessionRevision: session.journal.epoch,
      activeAgentRunId: null,
      ...page,
      lastEventId: session.journal.latestId,
    };
  }

  async getTimeline(
    workspaceId: string,
    sessionId: string,
    request: TimelinePageRequest,
  ): Promise<TimelineSnapshot> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const session = workspace.sessions.get(sessionId);
    if (!session) throw new HttpError(404, "session_not_found", "TSPi session was not found");
    if (!session.persisted) {
      throw new HttpError(
        409,
        "session_timeline_unavailable",
        "Structured timeline is available after the Pi session history is persisted",
      );
    }
    const page = await this.#registry.readPersistedSessionTimeline(
      workspace.workspace,
      session.persisted,
      request,
    );
    const selectedActive = page.history.selectedBranchId === page.history.activeBranchId;
    return {
      schemaVersion: "ts-phone-timeline/1",
      sessionId,
      sessionRevision: session.journal.epoch,
      activeAgentRunId: session.activeAgentRunId ?? null,
      ...page,
      lastEventId: session.snapshotEventId ?? session.journal.latestId,
      capabilities: capabilitiesForSession(session, selectedActive),
    };
  }

  async prompt(workspaceId: string, sessionId: string, input: PromptInput): Promise<void> {
    const session = await this.#connectedSession(workspaceId, sessionId);
    this.#assertRevision(session, input.sessionRevision);
    if (session.activating || session.switching || this.#guardedWorkspaces.has(workspaceId)
      || this.#closing || (session.state !== "idle" && session.state !== "running")) {
      throw new HttpError(409, "session_not_ready", "The session is changing or requires recovery; refresh before sending");
    }
    const existing = session.messageCommands.get(input.clientMessageId);
    const digest = createHash("sha256").update(input.message).digest("hex");
    if (existing) {
      if (existing.digest !== digest) throw new HttpError(409, "message_id_conflict", "Message identity was already used with different content");
      return existing.result;
    }
    const problem = promptProblem(session);
    if (problem) throw new HttpError(409, problem, "The TSPi model is not ready to receive messages");
    const connection = session.connection!;
    session.pendingPrompts += 1;
    session.unstartedPrompts.add(input.clientMessageId);
    const command = (this.#workers.owns(workspaceId, sessionId)
      ? this.#workers.prompt(workspaceId, sessionId, input.message, session.state === "running").then(() => {
        if (session.connection !== connection) {
          throw new RuntimeError("command_ambiguous", "Session changed while waiting for Pi prompt acknowledgement");
        }
        session.journal.publish("input", {
          type: "input", source: "rpc", origin: "phone", preflightAccepted: true,
          text: input.message, clientMessageId: input.clientMessageId,
        }, { instanceEpoch: connection.instanceEpoch, sessionGeneration: connection.sessionGeneration });
      })
      : connection.sendCommand({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      type: "command.prompt",
      workspaceId,
      sessionId,
      instanceEpoch: connection.instanceEpoch,
      sessionGeneration: connection.sessionGeneration,
      clientMessageId: input.clientMessageId,
      message: input.message,
    })).catch((error) => {
      session.unstartedPrompts.delete(input.clientMessageId);
      session.observedPrompts.delete(input.clientMessageId);
      if (error instanceof RuntimeError && (error.code === "command_ambiguous" || error.code === "bridge_disconnected")) {
        session.state = "recovery_required";
        this.#publishState(session);
      }
      throw error;
    }).finally(() => { session.pendingPrompts -= 1; });
    session.messageCommands.set(input.clientMessageId, { digest, result: command });
    this.#trimMessageCommands(session.messageCommands);
    return command;
  }

  async abort(workspaceId: string, sessionId: string, input: AbortInput): Promise<void> {
    const session = await this.#connectedSession(workspaceId, sessionId);
    this.#assertRevision(session, input.sessionRevision);
    if (!session.activeAgentRunId) {
      throw new HttpError(409, "agent_not_running", "No agent run is active in this TSPi session");
    }
    if (input.agentRunId !== session.activeAgentRunId) {
      throw new HttpError(409, "agent_run_stale", "The requested agent run is no longer active");
    }
    const connection = session.connection!;
    await connection.sendCommand({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      type: "command.abort",
      workspaceId,
      sessionId,
      instanceEpoch: connection.instanceEpoch,
      sessionGeneration: connection.sessionGeneration,
      agentRunId: input.agentRunId,
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

  async close(): Promise<void> {
    this.#closing = true;
    clearInterval(this.#staleTimer);
    for (const workspace of this.#records.values()) {
      for (const session of workspace.sessions.values()) session.connection?.close();
    }
    this.#approvals.clear();
    for (const waiters of this.#bridgeWaiters.values()) {
      for (const resolve of waiters) resolve();
    }
    this.#bridgeWaiters.clear();
    await this.#workers.close();
    await Promise.allSettled([...this.#activations.values()].map((activation) => activation.result));
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
      const { agentRunId, ...bridgeSnapshot } = bridgeRecord.snapshot;
      const projected = projectSnapshotMessagePage(
        bridgeRecord.snapshot.messages,
        bridgeRecord.snapshot.messageIds,
      );
      const hasMore = Boolean(projected.messageIds?.length)
        && (bridgeRecord.snapshot.hasMore === true || projected.omitted > 0);
      const snapshot: SessionSnapshot = {
        ...bridgeSnapshot,
        messages: projected.messages,
      };
      if (projected.messageIds !== undefined) {
        snapshot.messageIds = projected.messageIds;
        snapshot.hasMore = hasMore;
        if (hasMore && projected.messageIds[0]) snapshot.nextBefore = projected.messageIds[0];
        else delete snapshot.nextBefore;
      } else {
        delete snapshot.messageIds;
        delete snapshot.hasMore;
        delete snapshot.nextBefore;
      }
      session.snapshot = snapshot;
      if (agentRunId) session.activeAgentRunId = agentRunId;
      else delete session.activeAgentRunId;
      if (snapshot.runtime) session.runtime = snapshot.runtime;
      else delete session.runtime;
      session.state = snapshot.isStreaming ? "running" : "idle";
      session.snapshotEventId = session.journal.publish(
        "session.snapshot",
        {
          ...this.#sessionSummary(session),
          ...snapshot,
          activeAgentRunId: session.activeAgentRunId ?? null,
          messages: [...snapshot.messages],
          accessMode: session.accessMode,
          historyAvailable: Boolean(session.persisted),
          historyOnly: false,
          canPrompt: canPrompt(session),
          promptProblem: promptProblem(session),
          capabilities: capabilitiesForSession(session),
        },
        identity,
      ).id;
      this.#publishState(session);
      this.#resolveBridgeWaiters(bridgeWaiterKey(session.workspaceId, session.sessionId));
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
    // Native input is emitted before preflight; owned RPC prompts are published
    // above only after the request-correlated acknowledgement arrives.
    if (bridgeRecord.eventType === "input") {
      const payload = bridgeRecord.payload as { source?: string; clientMessageId?: string } | null;
      const pending = payload?.clientMessageId ?? (payload?.source === "rpc"
        ? [...session.unstartedPrompts].find((id) => !session.observedPrompts.has(id)) : undefined);
      if (pending && session.unstartedPrompts.has(pending)) session.observedPrompts.add(pending);
    }
    if (bridgeRecord.eventType === "input"
      && this.#workers.owns(session.workspaceId, session.sessionId)
      && (bridgeRecord.payload as { source?: unknown } | null)?.source === "rpc") return;
    if (bridgeRecord.eventType === "agent_start") {
      const agentRunId = agentRunIdFromEvent(bridgeRecord.payload, "agent_start");
      if (session.activeAgentRunId && session.activeAgentRunId !== agentRunId) {
        throw new Error("Bridge started a new agent run before settling the active run");
      }
      session.activeAgentRunId = agentRunId;
      for (const id of session.observedPrompts) session.unstartedPrompts.delete(id);
      session.observedPrompts.clear();
      session.state = "running";
      if (session.snapshot) session.snapshot.isStreaming = true;
    }
    if (bridgeRecord.eventType === "agent_settled") {
      const agentRunId = agentRunIdFromEvent(bridgeRecord.payload, "agent_settled");
      if (session.activeAgentRunId !== agentRunId) {
        throw new Error("Bridge settled an agent run that was not active");
      }
      delete session.activeAgentRunId;
      // Pi's settled event excludes queued continuations. Commands whose input
      // event has not arrived are still reserved, including the RPC/Bridge gap.
      for (const id of session.observedPrompts) session.unstartedPrompts.delete(id);
      session.observedPrompts.clear();
      session.state = "idle";
      if (session.snapshot) session.snapshot.isStreaming = false;
    }
    if (bridgeRecord.eventType === "message_end" && session.snapshot) {
      const message = messageFromEndEvent(bridgeRecord.payload);
      if (message !== undefined) {
        session.snapshot.messages = appendProjectedMessage(session.snapshot.messages, message);
        delete session.snapshot.messageIds;
        delete session.snapshot.hasMore;
        delete session.snapshot.nextBefore;
      }
    }
    const event = session.journal.publish(bridgeRecord.eventType, bridgeRecord.payload, identity);
    if (session.snapshot && (
      bridgeRecord.eventType === "message_end"
      || bridgeRecord.eventType === "agent_start"
      || bridgeRecord.eventType === "agent_settled"
    )) {
      session.snapshotEventId = event.id;
    }
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
    delete session.activeAgentRunId;
    session.messageCommands.clear();
    session.state = session.state === "running" || session.state === "recovery_required"
      || session.unstartedPrompts.size > 0 ? "recovery_required" : "offline";
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
      throw new HttpError(409, "session_offline", "Continue this conversation from Phone or start its TSPi runtime");
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
    const managedIds = new Set(this.#management.sessionIds(workspace.workspace.id));
    const sessionIds = new Set([...persisted.ids, ...managedIds]);
    for (const sessionId of sessionIds) {
      const diskSession = persisted.sessions.get(sessionId);
      const metadata = this.#management.session(workspace.workspace.id, sessionId);
      const existing = workspace.sessions.get(sessionId);
      if (existing) {
        if (diskSession) existing.persisted = diskSession;
        if (metadata && !isLive(existing) && !existing.activating) existing.accessMode = metadata.accessMode;
        continue;
      }
      this.#createSession(
        workspace,
        sessionId,
        metadata?.accessMode ?? "observer",
        diskSession,
      );
    }
    if (!persisted.complete) return;
    for (const [sessionId, session] of workspace.sessions) {
      if (persisted.ids.has(sessionId)) continue;
      delete session.persisted;
      if (!managedIds.has(sessionId) && !isLive(session) && !session.activating) this.#discardSession(workspace, sessionId);
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
      workspaceId: workspace.workspace.id,
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
      pendingPrompts: 0,
      unstartedPrompts: new Set(),
      observedPrompts: new Set(),
    };
    if (persisted) session.persisted = persisted;
    workspace.sessions.set(sessionId, session);
    return session;
  }

  #workspaceSummary(workspace: WorkspaceRecord): WorkspaceSummary {
    const metadata = this.#management.workspace(workspace.workspace.id);
    const sessions = [...workspace.sessions.values()].filter((session) => (
      (this.#management.session(workspace.workspace.id, session.sessionId)?.lifecycleState ?? "active") === "active"
    ));
    const live = sessions.filter((session) => session.connection && !session.connection.closed);
    const state = aggregateState(sessions.map((session) => session.state));
    return {
      id: workspace.workspace.id,
      name: metadata?.name ?? workspace.workspace.name,
      runtimeState: state,
      isStreaming: sessions.some((session) => session.state === "running"),
      liveSessionCount: live.length,
      sessionCount: sessions.length,
      lifecycleState: metadata?.lifecycleState ?? "active",
      managementRevision: metadata?.managementRevision ?? "unmanaged",
      managed: metadata !== undefined,
      ...(metadata?.updatedAt ? { updatedAt: metadata.updatedAt } : {}),
      ...(metadata?.deletedAt ? { deletedAt: metadata.deletedAt } : {}),
    };
  }

  #sessionSummary(session: SessionRecord): SessionSummary {
    const workspaceMetadata = this.#management.workspace(session.workspaceId);
    const metadata = this.#management.session(session.workspaceId, session.sessionId);
    const live = isLive(session);
    const historyAvailable = Boolean(session.persisted);
    const lifecycleState = metadata?.lifecycleState ?? "active";
    const updatedAt = [metadata?.updatedAt, session.persisted?.updatedAt, session.runtime?.updatedAt]
      .filter((value): value is string => Boolean(value))
      .sort().at(-1);
    const summary: SessionSummary = {
      sessionId: session.sessionId,
      sessionRevision: session.journal.epoch,
      activeAgentRunId: session.activeAgentRunId ?? null,
      runtimeState: session.state,
      isStreaming: session.state === "running",
      accessMode: live ? session.accessMode : metadata?.accessMode ?? session.accessMode,
      currentAccessMode: live && session.snapshot && !session.activating ? session.accessMode : null,
      runtimeOwner: this.#workers.owns(session.workspaceId, session.sessionId) ? "host" : live ? "external" : null,
      activation: this.#activationView(session),
      historyAvailable,
      historyOnly: session.state === "offline" && !live && historyAvailable,
      canPrompt: canPrompt(session) && lifecycleState === "active",
      ...(promptProblem(session) ? { promptProblem: promptProblem(session)! } : {}),
      capabilities: capabilitiesForSession(session),
      lifecycleState,
      managementRevision: metadata?.managementRevision ?? "unmanaged",
      managed: metadata !== undefined,
      canActivate: !session.activating && !session.switching && !live
        && session.state === "offline"
        && lifecycleState === "active"
        && (workspaceMetadata?.lifecycleState ?? "active") === "active"
        && this.#workers.available,
      ...(updatedAt ? { updatedAt } : {}),
      ...(metadata?.deletedAt ? { deletedAt: metadata.deletedAt } : {}),
    };
    if (metadata?.name) summary.sessionName = metadata.name;
    else if (session.snapshot?.sessionName) summary.sessionName = session.snapshot.sessionName;
    else if (session.persisted?.title) summary.sessionName = session.persisted.title;
    if (session.snapshot?.model) summary.model = session.snapshot.model;
    else if (session.runtime) {
      summary.model = `${session.runtime.model.provider}/${session.runtime.model.id}`;
    }
    else if (metadata?.model) summary.model = metadata.model;
    if (session.runtime) summary.runtime = session.runtime;
    return summary;
  }

  #publishState(session: SessionRecord): void {
    const connection = session.connection;
    const summary = this.#sessionSummary(session);
    session.journal.publish("session_state", {
      state: session.state,
      sessionId: session.sessionId,
      sessionName: session.snapshot?.sessionName,
      model: session.snapshot?.model,
      runtime: session.runtime,
      isStreaming: session.state === "running",
      activeAgentRunId: session.activeAgentRunId ?? null,
      accessMode: session.accessMode,
      historyAvailable: Boolean(session.persisted),
      historyOnly: session.state === "offline" && !isLive(session) && Boolean(session.persisted),
      canPrompt: canPrompt(session),
      promptProblem: promptProblem(session),
      capabilities: capabilitiesForSession(session),
      currentAccessMode: summary.currentAccessMode,
      runtimeOwner: summary.runtimeOwner,
      activation: summary.activation,
      canActivate: summary.canActivate,
      managementRevision: summary.managementRevision,
      lifecycleState: summary.lifecycleState,
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

  #trimMessageCommands(commands: SessionRecord["messageCommands"]): void {
    while (commands.size > 1_000) {
      const first = commands.keys().next().value as string | undefined;
      if (!first) break;
      commands.delete(first);
    }
  }

  #serializeMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.#mutationTail.then(operation);
    this.#mutationTail = result.then(() => undefined, () => undefined);
    return result;
  }

  async #managedSession(
    workspaceId: string,
    sessionId: string,
  ): Promise<{ workspace: WorkspaceRecord; session: SessionRecord }> {
    const workspace = await this.#loadWorkspace(workspaceId);
    await this.#reconcileSessions(workspace);
    const session = workspace.sessions.get(sessionId);
    if (!session) throw new HttpError(404, "session_not_found", "TSPi session was not found");
    return { workspace, session };
  }

  #workspaceName(workspace: WorkspaceRecord): string {
    return this.#management.workspace(workspace.workspace.id)?.name ?? workspace.workspace.name;
  }

  #sessionDefaults(session: SessionRecord): NewSessionMetadata {
    const name = session.snapshot?.sessionName;
    const model = session.snapshot?.model;
    return {
      accessMode: session.accessMode,
      ...(name ? { name } : {}),
      ...(model ? { model } : {}),
    };
  }

  async #stopIdleOwnedWorkers(workspace: WorkspaceRecord): Promise<void> {
    for (const session of workspace.sessions.values()) {
      if (this.#runtimeConflict(session).switchable) await this.#stopIdleWorker(session);
    }
  }

  async #stopIdleWorker(session: SessionRecord): Promise<void> {
    if (!this.#isIdleOwnedRuntime(session)) {
      throw new HttpError(409, "controller_session_active", "The current runtime is no longer idle; refresh before switching");
    }
    session.switching = true;
    this.#publishState(session);
    try {
      await this.#workers.stop(session.workspaceId, session.sessionId);
      session.connection?.close();
      session.state = "offline";
    } catch (error) {
      session.state = "recovery_required";
      throw error;
    } finally {
      delete session.switching;
      this.#publishState(session);
    }
  }

  async #withLifecycleGuard<T>(
    workspace: WorkspaceRecord,
    operation: (guard: LifecycleGuard) => Promise<T>,
  ): Promise<T> {
    const id = workspace.workspace.id;
    this.#guardedWorkspaces.add(id);
    try {
      return await this.#workers.withLifecycleGuard(id, workspace.workspace.root, operation);
    } finally {
      this.#guardedWorkspaces.delete(id);
    }
  }

  #blockingWorkerCount(workspace: WorkspaceRecord): number {
    return [...workspace.sessions.values()].filter((session) => (
      !this.#runtimeConflict(session).switchable
      && (
        isLive(session)
        || this.#workers.owns(workspace.workspace.id, session.sessionId)
        || session.state === "connecting"
        || session.state === "running"
      )
    )).length;
  }

  #workspaceApprovalCount(workspaceId: string): number {
    const prefix = `${workspaceId}\u0000`;
    return [...this.#approvals.keys()].filter((key) => key.startsWith(prefix)).length;
  }

  #sessionApprovalCount(workspaceId: string, sessionId: string): number {
    const prefix = `${workspaceId}\u0000${sessionId}\u0000`;
    return [...this.#approvals.keys()].filter((key) => key.startsWith(prefix)).length;
  }

  async #transitionSession(
    workspaceId: string,
    sessionId: string,
    input: LifecycleInput,
    lifecycleState: LifecycleState,
    stopIdleWorker = true,
  ): Promise<SessionSummary> {
    return this.#serializeMutation(async () => {
      const { workspace, session } = await this.#managedSession(workspaceId, sessionId);
      this.#assertSessionManagementRevision(
        workspaceId,
        sessionId,
        input.managementRevision,
      );
      if (lifecycleState !== "active") {
        if (stopIdleWorker && this.#runtimeConflict(session).switchable) await this.#stopIdleWorker(session);
        this.#assertSessionCanHide(workspaceId, session);
      }
      await this.#management.transitionSession(
        workspaceId,
        this.#workspaceName(workspace),
        sessionId,
        input.managementRevision,
        lifecycleState,
        this.#sessionDefaults(session),
      );
      return this.#sessionSummary(session);
    });
  }

  #assertWorkspaceManagementRevision(
    workspaceId: string,
    expectedRevision: string,
  ): void {
    this.#assertNoActivation(workspaceId);
    const actual = this.#management.workspace(workspaceId)?.managementRevision
      ?? "unmanaged";
    if (actual !== expectedRevision) {
      throw new HttpError(
        409,
        "workspace_management_changed",
        "Workspace changed; refresh and try again",
      );
    }
  }

  #assertSessionManagementRevision(
    workspaceId: string,
    sessionId: string,
    expectedRevision: string,
  ): void {
    this.#assertNoActivation(workspaceId);
    const actual = this.#management.session(workspaceId, sessionId)
      ?.managementRevision ?? "unmanaged";
    if (actual !== expectedRevision) {
      throw new HttpError(
        409,
        "session_management_changed",
        "Session changed; refresh and try again",
      );
    }
  }

  #assertSessionCanHide(workspaceId: string, session: SessionRecord): void {
    if (isLive(session)
      || this.#workers.owns(workspaceId, session.sessionId)
      || session.state === "connecting"
      || session.state === "running") {
      throw new HttpError(409, "session_active", "Stop the TSPi session before hiding it");
    }
    if (this.#sessionApprovalCount(workspaceId, session.sessionId) > 0) {
      throw new HttpError(409, "session_has_pending_approvals", "Resolve pending approvals before hiding the session");
    }
  }

  #controller(workspace: WorkspaceRecord): SessionRecord | undefined {
    return [...workspace.sessions.values()].find((session) => (
      session.accessMode === "controller"
      && (isLive(session) || this.#workers.owns(workspace.workspace.id, session.sessionId))
    ));
  }

  #runtimeConflict(session: SessionRecord): NonNullable<SessionActivation["conflict"]> {
    const owned = this.#workers.owns(session.workspaceId, session.sessionId);
    const name = this.#management.session(session.workspaceId, session.sessionId)?.name
      ?? session.snapshot?.sessionName ?? session.persisted?.title;
    return {
      sessionId: session.sessionId,
      sessionRevision: session.journal.epoch,
      ...(name ? { sessionName: name } : {}),
      owner: owned ? "host" : "external",
      switchable: this.#isIdleOwnedRuntime(session) && !session.activating && !session.switching,
    };
  }

  #isIdleOwnedRuntime(session: SessionRecord): boolean {
    return this.#workers.owns(session.workspaceId, session.sessionId) && isLive(session)
      && session.state === "idle" && session.pendingPrompts === 0 && session.unstartedPrompts.size === 0
      && !session.activeAgentRunId && this.#sessionApprovalCount(session.workspaceId, session.sessionId) === 0;
  }

  #activationView(session: SessionRecord): SessionActivation {
    const metadata = this.#management.session(session.workspaceId, session.sessionId);
    const workspace = this.#records.get(session.workspaceId);
    if (this.#closing || !this.#workers.available || !workspace) return { modes: [], problem: "worker_unavailable" };
    if ((metadata?.lifecycleState ?? "active") !== "active"
      || (this.#management.workspace(session.workspaceId)?.lifecycleState ?? "active") !== "active") {
      return { modes: [], problem: "session_not_active" };
    }
    if (session.activating || session.switching || this.#activations.has(session.workspaceId)) {
      return { modes: [], problem: "workspace_activating" };
    }
    if (session.state === "recovery_required" || (!isLive(session) && this.#workers.owns(session.workspaceId, session.sessionId))) {
      return { modes: [], problem: "session_recovery_required" };
    }
    const controller = this.#controller(workspace);
    if (isLive(session) && session.accessMode === "observer" && controller && controller !== session) {
      return { modes: ["observer"], conflict: { ...this.#runtimeConflict(controller), switchable: false } };
    }
    const current = isLive(session) ? session : controller;
    if (current) {
      const conflict = this.#runtimeConflict(current);
      const modes: SessionAccessMode[] = isLive(session)
        ? [session.accessMode]
        : ["observer"];
      if (conflict.switchable) modes.push(session.accessMode === "controller" && isLive(session) ? "observer" : "controller");
      return { modes, conflict };
    }
    return { modes: ["controller", "observer"] };
  }

  #assertNoActivation(workspaceId: string): void {
    if (this.#activations.has(workspaceId)) {
      throw new HttpError(409, "workspace_activating", "Wait for conversation activation before changing its lifecycle");
    }
  }

  #bridgeWaiter(key: string): { promise: Promise<void>; resolve: () => void } {
    let resolve!: () => void;
    const promise = new Promise<void>((done) => { resolve = done; });
    const waiters = this.#bridgeWaiters.get(key) ?? new Set<() => void>();
    waiters.add(resolve);
    this.#bridgeWaiters.set(key, waiters);
    return { promise, resolve };
  }

  #cancelBridgeWaiter(key: string, resolve: () => void): void {
    const waiters = this.#bridgeWaiters.get(key);
    if (!waiters) return;
    waiters.delete(resolve);
    if (waiters.size === 0) this.#bridgeWaiters.delete(key);
  }

  #resolveBridgeWaiters(key: string): void {
    const waiters = this.#bridgeWaiters.get(key);
    if (!waiters) return;
    this.#bridgeWaiters.delete(key);
    for (const resolve of waiters) resolve();
  }
}

function approvalKey(workspaceId: string, sessionId: string, approvalId: string): string {
  return `${workspaceId}\u0000${sessionId}\u0000${approvalId}`;
}

function bridgeWaiterKey(workspaceId: string, sessionId: string): string {
  return `${workspaceId}\u0000${sessionId}`;
}

function nextWorkspaceId(ids: Iterable<string>): string {
  let highest = 0;
  for (const id of ids) {
    const match = /^ts_([0-9]+)$/.exec(id);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return `ts_${String(highest + 1).padStart(3, "0")}`;
}

function nextSessionId(ids: Iterable<string>): string {
  let highest = 0;
  for (const id of ids) {
    const match = /^session_([0-9]+)$/.exec(id);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return `session_${highest + 1}`;
}

function sameActivation(left: ActivateInput, right: ActivateInput): boolean {
  return left.requestId === right.requestId && left.accessMode === right.accessMode
    && left.managementRevision === right.managementRevision
    && left.switchFrom?.sessionId === right.switchFrom?.sessionId
    && left.switchFrom?.sessionRevision === right.switchFrom?.sessionRevision;
}

function cloneActivation(input: ActivateInput): ActivateInput {
  return { ...input, ...(input.switchFrom ? { switchFrom: { ...input.switchFrom } } : {}) };
}

function workerStartError(exit: WorkerExit): HttpError {
  if (exit.startupError) return exit.startupError;
  // Launcher/provider stderr can contain private configuration. Expose only
  // process outcome; model readiness failures already have specific safe codes.
  const detail = exit.signal
    ? `TSPi Worker stopped before readiness with ${exit.signal}`
    : `TSPi Worker exited before readiness with code ${exit.code ?? "unknown"}`;
  return new HttpError(502, "worker_start_failed", detail);
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

function agentRunIdFromEvent(payload: unknown, eventType: "agent_start" | "agent_settled"): string {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error(`${eventType} payload must be an object`);
  }
  const agentRunId = (payload as Record<string, unknown>).agentRunId;
  if (typeof agentRunId !== "string" || !/^[A-Za-z0-9._:-]{1,160}$/.test(agentRunId)) {
    throw new Error(`${eventType} payload must include a valid agentRunId`);
  }
  return agentRunId;
}

function messagePageFromSnapshot(snapshot: SessionSnapshot, limit: number): MessagePage {
  const messages = snapshot.messages.slice(-limit);
  if (!snapshot.messageIds) return { messages, hasMore: false };
  const messageIds = snapshot.messageIds.slice(-limit);
  const hasMore = snapshot.hasMore === true || messages.length < snapshot.messages.length;
  return {
    messages,
    messageIds,
    hasMore,
    ...(hasMore && messageIds[0] ? { nextBefore: messageIds[0] } : {}),
  };
}

function isLive(session: SessionRecord): boolean {
  return Boolean(session.connection && !session.connection.closed);
}

function promptProblem(session: SessionRecord): SessionSnapshot["promptProblem"] {
  if (!isLive(session)) return undefined;
  if (session.snapshot?.promptProblem) return session.snapshot.promptProblem;
  const model = session.snapshot?.model;
  if (!model || model === "unknown/unknown") return "model_unavailable";
  return undefined;
}

function canPrompt(session: SessionRecord): boolean {
  return isLive(session) && !session.activating && !session.switching
    && (session.state === "idle" || session.state === "running") && !promptProblem(session);
}

function capabilitiesForSession(
  session: SessionRecord,
  activeBranch = true,
): SessionCapability[] {
  const capabilities: SessionCapability[] = ["history.messages", "activity.tools"];
  if (session.persisted) {
    capabilities.push(
      "history.timeline",
      "history.pagination",
      "history.seek",
      "history.branches",
      "activity.subagents",
      "activity.research",
    );
  }
  capabilities.push("session.activate_mode");
  if (activeBranch && isLive(session)) {
    if (canPrompt(session)) capabilities.push("command.prompt");
    capabilities.push("command.abort", "interaction.approval");
  }
  return capabilities;
}
