import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { mkdir, open, rename, rm } from "node:fs/promises";
import { join } from "node:path";
import { HttpError } from "./errors.js";
import type { LifecycleState, SessionAccessMode } from "./types.js";

const MANAGEMENT_SCHEMA = "ts-phone-management/1";
const MANAGEMENT_FILE = "management.json";
const MAX_MANAGEMENT_BYTES = 1024 * 1024;

export interface ManagedSession {
  name?: string;
  model?: string;
  accessMode: SessionAccessMode;
  lifecycleState: LifecycleState;
  managementRevision: string;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string;
}

export interface ManagedWorkspace {
  name: string;
  lifecycleState: LifecycleState;
  managementRevision: string;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string;
  sessions: Record<string, ManagedSession>;
}

interface ManagementDocument {
  schemaVersion: typeof MANAGEMENT_SCHEMA;
  workspaces: Record<string, ManagedWorkspace>;
}

export interface NewSessionMetadata {
  name?: string;
  model?: string;
  accessMode: SessionAccessMode;
}

export class ManagementStore {
  readonly #stateDir: string;
  #document: ManagementDocument;
  #tail: Promise<void> = Promise.resolve();

  private constructor(stateDir: string, document: ManagementDocument) {
    this.#stateDir = stateDir;
    this.#document = document;
  }

  static async open(stateDir: string): Promise<ManagementStore> {
    await mkdir(stateDir, { recursive: true, mode: 0o700 });
    return new ManagementStore(stateDir, await readDocument(join(stateDir, MANAGEMENT_FILE)));
  }

  workspace(workspaceId: string): ManagedWorkspace | undefined {
    return clone(this.#document.workspaces[workspaceId]);
  }

  session(workspaceId: string, sessionId: string): ManagedSession | undefined {
    return clone(this.#document.workspaces[workspaceId]?.sessions[sessionId]);
  }

  workspaceIds(): string[] {
    return Object.keys(this.#document.workspaces);
  }

  sessionIds(workspaceId: string): string[] {
    return Object.keys(this.#document.workspaces[workspaceId]?.sessions ?? {});
  }

  async createWorkspace(
    workspaceId: string,
    name: string,
    sessionId: string,
    session: NewSessionMetadata,
  ): Promise<ManagedWorkspace> {
    return this.#mutate((document) => {
      if (document.workspaces[workspaceId]) {
        throw new HttpError(409, "workspace_exists", "Workspace already exists");
      }
      const now = new Date().toISOString();
      const created: ManagedWorkspace = {
        name,
        lifecycleState: "active",
        managementRevision: randomUUID(),
        createdAt: now,
        updatedAt: now,
        sessions: {
          [sessionId]: createSessionRecord(session, now),
        },
      };
      document.workspaces[workspaceId] = created;
      return clone(created)!;
    });
  }

  async createSession(
    workspaceId: string,
    workspaceName: string,
    sessionId: string,
    session: NewSessionMetadata,
  ): Promise<ManagedSession> {
    return this.#mutate((document) => {
      const workspace = ensureWorkspace(document, workspaceId, workspaceName);
      if (workspace.lifecycleState !== "active") {
        throw new HttpError(409, "workspace_not_active", "Restore the workspace before creating a session");
      }
      if (workspace.sessions[sessionId]) {
        throw new HttpError(409, "session_exists", "Session already exists");
      }
      const now = new Date().toISOString();
      const created = createSessionRecord(session, now);
      workspace.sessions[sessionId] = created;
      touch(workspace, now);
      return clone(created)!;
    });
  }

  async ensureSession(
    workspaceId: string,
    workspaceName: string,
    sessionId: string,
    expectedRevision: string,
    defaults: NewSessionMetadata,
  ): Promise<ManagedSession> {
    return this.#mutate((document) => {
      const workspace = ensureWorkspace(document, workspaceId, workspaceName);
      const existing = workspace.sessions[sessionId];
      if (existing) {
        assertRevision(existing.managementRevision, expectedRevision, "session");
        return clone(existing)!;
      }
      assertRevision("unmanaged", expectedRevision, "session");
      const now = new Date().toISOString();
      const created = createSessionRecord(defaults, now);
      workspace.sessions[sessionId] = created;
      touch(workspace, now);
      return clone(created)!;
    });
  }

  async rememberSessionModel(workspaceId: string, workspaceName: string, sessionId: string,
    model: string, defaults: NewSessionMetadata): Promise<void> {
    await this.#mutate((document) => {
      const workspace = ensureWorkspace(document, workspaceId, workspaceName);
      const session = workspace.sessions[sessionId] ?? createSessionRecord(defaults, new Date().toISOString());
      session.model = model;
      revise(session);
      workspace.sessions[sessionId] = session;
      touch(workspace, session.updatedAt);
    });
  }

  async renameWorkspace(
    workspaceId: string,
    fallbackName: string,
    expectedRevision: string,
    name: string,
  ): Promise<ManagedWorkspace> {
    return this.#mutate((document) => {
      const workspace = workspaceForMutation(document, workspaceId, fallbackName, expectedRevision);
      workspace.name = name;
      revise(workspace);
      return clone(workspace)!;
    });
  }

  async rememberSessionActivation(
    workspaceId: string,
    workspaceName: string,
    sessionId: string,
    expectedRevision: string,
    defaults: NewSessionMetadata,
  ): Promise<ManagedSession> {
    return this.#mutate((document) => {
      const workspace = ensureWorkspace(document, workspaceId, workspaceName);
      const session = sessionForMutation(workspace, sessionId, expectedRevision, defaults);
      if (workspace.lifecycleState !== "active" || session.lifecycleState !== "active") {
        throw new HttpError(409, "session_not_active", "Restore the workspace and conversation before continuing");
      }
      session.accessMode = defaults.accessMode;
      revise(session);
      touch(workspace, session.updatedAt);
      return clone(session)!;
    });
  }

  async renameSession(
    workspaceId: string,
    workspaceName: string,
    sessionId: string,
    expectedRevision: string,
    name: string,
    defaults: NewSessionMetadata,
  ): Promise<ManagedSession> {
    return this.#mutate((document) => {
      const workspace = ensureWorkspace(document, workspaceId, workspaceName);
      const session = sessionForMutation(workspace, sessionId, expectedRevision, defaults);
      session.name = name;
      revise(session);
      touch(workspace, session.updatedAt);
      return clone(session)!;
    });
  }

  async transitionWorkspace(
    workspaceId: string,
    fallbackName: string,
    expectedRevision: string,
    lifecycleState: LifecycleState,
  ): Promise<ManagedWorkspace> {
    return this.#mutate((document) => {
      const workspace = workspaceForMutation(document, workspaceId, fallbackName, expectedRevision);
      transition(workspace, lifecycleState);
      return clone(workspace)!;
    });
  }

  async transitionSession(
    workspaceId: string,
    workspaceName: string,
    sessionId: string,
    expectedRevision: string,
    lifecycleState: LifecycleState,
    defaults: NewSessionMetadata,
  ): Promise<ManagedSession> {
    return this.#mutate((document) => {
      const workspace = ensureWorkspace(document, workspaceId, workspaceName);
      const session = sessionForMutation(workspace, sessionId, expectedRevision, defaults);
      transition(session, lifecycleState);
      touch(workspace, session.updatedAt);
      return clone(session)!;
    });
  }

  async purgeWorkspace(workspaceId: string, expectedRevision: string): Promise<void> {
    await this.#mutate((document) => {
      const workspace = document.workspaces[workspaceId];
      if (!workspace) throw new HttpError(404, "workspace_not_found", "Workspace does not exist");
      assertRevision(workspace.managementRevision, expectedRevision, "workspace");
      if (workspace.lifecycleState !== "trashed") {
        throw new HttpError(409, "workspace_not_trashed", "Move the workspace to Recently Deleted before purging it");
      }
      delete document.workspaces[workspaceId];
    });
  }

  async restorePurgedWorkspace(
    workspaceId: string,
    snapshot: ManagedWorkspace,
  ): Promise<void> {
    await this.#mutate((document) => {
      if (document.workspaces[workspaceId]) {
        throw new Error("Cannot recover purged workspace because its management record exists");
      }
      if (snapshot.lifecycleState !== "trashed") {
        throw new Error("Cannot recover a workspace snapshot that is not trashed");
      }
      document.workspaces[workspaceId] = clone(snapshot)!;
    });
  }

  async purgeSession(
    workspaceId: string,
    sessionId: string,
    expectedRevision: string,
  ): Promise<void> {
    await this.#mutate((document) => {
      const workspace = document.workspaces[workspaceId];
      const session = workspace?.sessions[sessionId];
      if (!workspace || !session) throw new HttpError(404, "session_not_found", "Session does not exist");
      assertRevision(session.managementRevision, expectedRevision, "session");
      if (session.lifecycleState !== "trashed") {
        throw new HttpError(409, "session_not_trashed", "Move the session to Recently Deleted before purging it");
      }
      delete workspace.sessions[sessionId];
      touch(workspace);
    });
  }

  async restorePurgedSession(
    workspaceId: string,
    sessionId: string,
    workspaceSnapshot: ManagedWorkspace,
  ): Promise<void> {
    await this.#mutate((document) => {
      const current = document.workspaces[workspaceId];
      const snapshot = workspaceSnapshot.sessions[sessionId];
      if (!current || current.sessions[sessionId]) {
        throw new Error("Cannot recover purged session because its management state changed");
      }
      if (!snapshot || snapshot.lifecycleState !== "trashed") {
        throw new Error("Cannot recover a session snapshot that is not trashed");
      }
      document.workspaces[workspaceId] = clone(workspaceSnapshot)!;
    });
  }

  async #mutate<T>(operation: (document: ManagementDocument) => T): Promise<T> {
    const run = this.#tail.then(async () => {
      const next = clone(this.#document)!;
      const result = operation(next);
      await writeDocument(this.#stateDir, next);
      this.#document = next;
      return result;
    });
    this.#tail = run.then(() => undefined, () => undefined);
    return run;
  }
}

function createSessionRecord(input: NewSessionMetadata, now: string): ManagedSession {
  return {
    ...(input.name ? { name: input.name } : {}),
    ...(input.model ? { model: input.model } : {}),
    accessMode: input.accessMode,
    lifecycleState: "active",
    managementRevision: randomUUID(),
    createdAt: now,
    updatedAt: now,
  };
}

function ensureWorkspace(
  document: ManagementDocument,
  workspaceId: string,
  fallbackName: string,
): ManagedWorkspace {
  const existing = document.workspaces[workspaceId];
  if (existing) return existing;
  const now = new Date().toISOString();
  const created: ManagedWorkspace = {
    name: fallbackName,
    lifecycleState: "active",
    managementRevision: randomUUID(),
    createdAt: now,
    updatedAt: now,
    sessions: {},
  };
  document.workspaces[workspaceId] = created;
  return created;
}

function workspaceForMutation(
  document: ManagementDocument,
  workspaceId: string,
  fallbackName: string,
  expectedRevision: string,
): ManagedWorkspace {
  const existing = document.workspaces[workspaceId];
  if (existing) {
    assertRevision(existing.managementRevision, expectedRevision, "workspace");
    return existing;
  }
  assertRevision("unmanaged", expectedRevision, "workspace");
  return ensureWorkspace(document, workspaceId, fallbackName);
}

function sessionForMutation(
  workspace: ManagedWorkspace,
  sessionId: string,
  expectedRevision: string,
  defaults: NewSessionMetadata,
): ManagedSession {
  const existing = workspace.sessions[sessionId];
  if (existing) {
    assertRevision(existing.managementRevision, expectedRevision, "session");
    return existing;
  }
  assertRevision("unmanaged", expectedRevision, "session");
  const created = createSessionRecord(defaults, new Date().toISOString());
  workspace.sessions[sessionId] = created;
  return created;
}

function assertRevision(actual: string, expected: string, resource: string): void {
  if (actual !== expected) {
    throw new HttpError(409, `${resource}_management_changed`, `${capitalize(resource)} changed; refresh and try again`);
  }
}

function transition(
  record: Pick<ManagedWorkspace, "lifecycleState" | "managementRevision" | "updatedAt" | "deletedAt">,
  lifecycleState: LifecycleState,
): void {
  if (record.lifecycleState === lifecycleState) {
    throw new HttpError(409, "lifecycle_unchanged", `Resource is already ${lifecycleState}`);
  }
  const now = new Date();
  record.lifecycleState = lifecycleState;
  record.managementRevision = randomUUID();
  record.updatedAt = now.toISOString();
  if (lifecycleState === "trashed") {
    record.deletedAt = now.toISOString();
  } else {
    delete record.deletedAt;
  }
}

function revise(record: { managementRevision: string; updatedAt: string }): void {
  record.managementRevision = randomUUID();
  record.updatedAt = new Date().toISOString();
}

function touch(workspace: ManagedWorkspace, at = new Date().toISOString()): void {
  workspace.managementRevision = randomUUID();
  workspace.updatedAt = at;
}

async function readDocument(path: string): Promise<ManagementDocument> {
  let handle;
  try {
    handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > MAX_MANAGEMENT_BYTES || (stat.mode & 0o077) !== 0) {
      throw new Error("TS Phone management store is unsafe");
    }
    const value = JSON.parse(await handle.readFile("utf8")) as unknown;
    return parseDocument(value);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return { schemaVersion: MANAGEMENT_SCHEMA, workspaces: {} };
    }
    throw error;
  } finally {
    await handle?.close();
  }
}

async function writeDocument(stateDir: string, document: ManagementDocument): Promise<void> {
  const serialized = `${JSON.stringify(document, null, 2)}\n`;
  if (Buffer.byteLength(serialized, "utf8") > MAX_MANAGEMENT_BYTES) {
    throw new HttpError(409, "management_capacity_exceeded", "Project and session metadata exceeds the Host storage limit");
  }
  const destination = join(stateDir, MANAGEMENT_FILE);
  const temporary = join(stateDir, `.management.${randomUUID()}.tmp`);
  try {
    const handle = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
    try {
      await handle.writeFile(serialized, "utf8");
      await handle.sync();
    } finally {
      await handle.close();
    }
    await rename(temporary, destination);
    const directory = await open(stateDir, constants.O_RDONLY);
    try {
      await directory.sync();
    } finally {
      await directory.close();
    }
  } catch (error) {
    try {
      await rm(temporary, { force: true });
    } catch {
      // The atomic rename may already have consumed the temporary path.
    }
    throw error;
  }
}

function parseDocument(value: unknown): ManagementDocument {
  if (!isRecord(value)
    || value.schemaVersion !== MANAGEMENT_SCHEMA
    || !isRecord(value.workspaces)
    || Object.keys(value).some((key) => key !== "schemaVersion" && key !== "workspaces")) {
    throw new Error("TS Phone management store is invalid");
  }
  const workspaces: Record<string, ManagedWorkspace> = {};
  for (const [workspaceId, candidate] of Object.entries(value.workspaces)) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(workspaceId)) {
      throw new Error("TS Phone management store contains an invalid workspace id");
    }
    workspaces[workspaceId] = parseWorkspace(candidate);
  }
  return { schemaVersion: MANAGEMENT_SCHEMA, workspaces };
}

function parseWorkspace(value: unknown): ManagedWorkspace {
  if (!isRecord(value)) throw new Error("TS Phone management workspace is invalid");
  const allowed = new Set([
    "name", "lifecycleState", "managementRevision", "createdAt", "updatedAt",
    "deletedAt", "sessions",
  ]);
  if (Object.keys(value).some((key) => !allowed.has(key))
    || !validName(value.name)
    || !validLifecycle(value.lifecycleState)
    || !validRevision(value.managementRevision)
    || !validTimestamp(value.createdAt)
    || !validTimestamp(value.updatedAt)
    || !validDeletionFields(value)
    || !isRecord(value.sessions)) {
    throw new Error("TS Phone management workspace is invalid");
  }
  const sessions: Record<string, ManagedSession> = {};
  for (const [sessionId, candidate] of Object.entries(value.sessions)) {
    if (!/^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,158}[A-Za-z0-9])?$/.test(sessionId)) {
      throw new Error("TS Phone management store contains an invalid session id");
    }
    sessions[sessionId] = parseSession(candidate);
  }
  return {
    name: value.name,
    lifecycleState: value.lifecycleState,
    managementRevision: value.managementRevision,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    ...(typeof value.deletedAt === "string" ? { deletedAt: value.deletedAt } : {}),
    sessions,
  };
}

function parseSession(value: unknown): ManagedSession {
  if (!isRecord(value)) throw new Error("TS Phone management session is invalid");
  const allowed = new Set([
    "name", "model", "accessMode", "lifecycleState", "managementRevision",
    "createdAt", "updatedAt", "deletedAt",
  ]);
  if (Object.keys(value).some((key) => !allowed.has(key))
    || (value.name !== undefined && !validName(value.name))
    || (value.model !== undefined && !validModel(value.model))
    || (value.accessMode !== "controller" && value.accessMode !== "observer")
    || !validLifecycle(value.lifecycleState)
    || !validRevision(value.managementRevision)
    || !validTimestamp(value.createdAt)
    || !validTimestamp(value.updatedAt)
    || !validDeletionFields(value)) {
    throw new Error("TS Phone management session is invalid");
  }
  return {
    ...(typeof value.name === "string" ? { name: value.name } : {}),
    ...(typeof value.model === "string" ? { model: value.model } : {}),
    accessMode: value.accessMode,
    lifecycleState: value.lifecycleState,
    managementRevision: value.managementRevision,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    ...(typeof value.deletedAt === "string" ? { deletedAt: value.deletedAt } : {}),
  };
}

function validDeletionFields(value: Record<string, unknown>): boolean {
  if (value.lifecycleState === "trashed") {
    return validTimestamp(value.deletedAt);
  }
  return value.deletedAt === undefined;
}

function validName(value: unknown): value is string {
  return typeof value === "string"
    && value.trim() === value
    && value.length >= 1
    && value.length <= 120
    && !/[\u0000-\u001f\u007f]/.test(value);
}

function validModel(value: unknown): value is string {
  return typeof value === "string"
    && value.length >= 1
    && value.length <= 200
    && /^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(value);
}

function validLifecycle(value: unknown): value is LifecycleState {
  return value === "active" || value === "archived" || value === "trashed";
}

function validRevision(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f-]{36}$/.test(value);
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function isRecord(value: unknown): value is Record<string, any> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function clone<T>(value: T): T {
  return value === undefined ? value : structuredClone(value);
}

function capitalize(value: string): string {
  return `${value.slice(0, 1).toUpperCase()}${value.slice(1)}`;
}
