import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat, mkdir, open, readdir, realpath, rename, rm, type FileHandle } from "node:fs/promises";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { createInterface } from "node:readline";
import { HttpError } from "./errors.js";
import { historyPage } from "./history-page.js";
import {
  MAX_SNAPSHOT_MESSAGES,
  projectMessage,
  type ProjectedMessageRecord,
} from "./message-projection.js";
import {
  projectTimeline,
  timelineBranchSummary,
  timelineHistorySummary,
  type SessionTimelineEntry,
} from "./timeline-projection.js";
import type {
  MessagePage,
  MessagePageRequest,
  TimelinePage,
  TimelinePageRequest,
} from "./types.js";

export const WORKSPACE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
const PI_SESSION_ID_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,158}[A-Za-z0-9])?$/;
const MAX_SESSION_HEADER_BYTES = 1024 * 1024;
const MAX_SESSION_FILE_BYTES = 64 * 1024 * 1024;
const PI_MESSAGE_ID_PATTERN = /^[0-9a-f]{8}$/;
const MAX_SESSION_BRANCHES = 128;
const MAX_CACHED_SESSION_BYTES = 32 * 1024 * 1024;
const MAX_CACHED_SESSIONS = 8;
const MAX_SESSION_TITLE_BYTES = 64 * 1024;
const MAX_CACHED_PREVIEWS = 256;

export interface RegisteredWorkspace {
  id: string;
  name: string;
  root: string;
}

export interface PersistedSessionIndex {
  ids: ReadonlySet<string>;
  sessions: ReadonlyMap<string, PersistedSession>;
  complete: boolean;
}

export interface PersistedSession {
  id: string;
  filePath: string;
  title?: string;
  updatedAt?: string;
}

export interface QuarantinedPath {
  original: string;
  quarantine: string;
}

export class WorkspaceRegistry {
  readonly #configuredRoot: string;
  readonly #graphs = new Map<string, { version: string; bytes: number; graph: PiSessionGraph }>();
  readonly #previews = new Map<string, { version: string; preview: PiSessionPreview }>();

  constructor(root: string) {
    this.#configuredRoot = resolve(root);
  }

  async list(): Promise<RegisteredWorkspace[]> {
    const root = await this.#resolvedRoot();
    const entries = await readdir(root, { withFileTypes: true });
    const workspaces: RegisteredWorkspace[] = [];
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.isSymbolicLink() || !WORKSPACE_NAME_PATTERN.test(entry.name)) continue;
      try {
        workspaces.push(await this.get(entry.name));
      } catch (error) {
        if (!(error instanceof HttpError)) throw error;
      }
    }
    return workspaces.sort((left, right) => left.name.localeCompare(right.name));
  }

  async get(name: string): Promise<RegisteredWorkspace> {
    if (!WORKSPACE_NAME_PATTERN.test(name)) {
      throw new HttpError(400, "invalid_workspace", "Workspace name is invalid");
    }
    const root = await this.#resolvedRoot();
    const candidate = join(root, name);
    let stat;
    try {
      stat = await lstat(candidate);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        throw new HttpError(404, "workspace_not_found", "Workspace does not exist");
      }
      throw error;
    }
    if (!stat.isDirectory() || stat.isSymbolicLink()) {
      throw new HttpError(400, "unsafe_workspace", "Workspace must be a real directory");
    }
    const resolved = await realpath(candidate);
    const relation = relative(root, resolved);
    if (relation === "" || relation.startsWith("..") || relation.includes("/../")) {
      throw new HttpError(400, "unsafe_workspace", "Workspace escaped the configured root");
    }
    return { id: name, name, root: resolved };
  }

  async create(name: string): Promise<RegisteredWorkspace> {
    if (!WORKSPACE_NAME_PATTERN.test(name)) {
      throw new HttpError(400, "invalid_workspace", "Workspace name is invalid");
    }
    const root = await this.#resolvedRoot();
    const candidate = join(root, name);
    try {
      await mkdir(candidate, { mode: 0o700 });
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "EEXIST") {
        throw new HttpError(409, "workspace_exists", "Workspace already exists");
      }
      throw error;
    }
    return this.get(name);
  }

  async quarantineWorkspace(workspace: RegisteredWorkspace): Promise<QuarantinedPath> {
    const root = await this.#resolvedRoot();
    await this.#assertCurrentWorkspace(workspace);
    const quarantine = join(root, `.ts-phone-purge-${randomUUID()}`);
    await rename(workspace.root, quarantine);
    return { original: workspace.root, quarantine };
  }

  async quarantineSession(
    workspace: RegisteredWorkspace,
    session: PersistedSession,
  ): Promise<QuarantinedPath> {
    await this.#assertCurrentWorkspace(workspace);
    const sessionsRoot = join(workspace.root, ".pi", "sessions");
    const sessionsStat = await lstat(sessionsRoot);
    if (!sessionsStat.isDirectory()
      || sessionsStat.isSymbolicLink()
      || await realpath(sessionsRoot) !== sessionsRoot) {
      throw new HttpError(409, "session_history_unsafe", "Session history cannot be purged safely");
    }
    const relation = relative(sessionsRoot, session.filePath);
    if (!relation || relation.startsWith("..") || isAbsolute(relation) || relation.includes(sep)) {
      throw new HttpError(409, "session_history_unsafe", "Session history cannot be purged safely");
    }
    const stat = await lstat(session.filePath);
    if (!stat.isFile() || stat.isSymbolicLink()) {
      throw new HttpError(409, "session_history_unsafe", "Session history cannot be purged safely");
    }
    const quarantine = join(sessionsRoot, `.ts-phone-purge-${randomUUID()}`);
    await rename(session.filePath, quarantine);
    return { original: session.filePath, quarantine };
  }

  async restoreQuarantine(value: QuarantinedPath): Promise<void> {
    await rename(value.quarantine, value.original);
  }

  async deleteQuarantine(value: QuarantinedPath): Promise<void> {
    await rm(value.quarantine, { recursive: true, force: false });
  }

  async listPersistedSessionIds(workspace: RegisteredWorkspace): Promise<PersistedSessionIndex> {
    const piRoot = join(workspace.root, ".pi");
    const sessionsRoot = join(piRoot, "sessions");
    const piState = await directoryState(piRoot);
    if (piState === "missing") return emptySessionIndex();
    if (piState !== "directory") throw new Error(`Workspace Pi state path is unsafe: ${piRoot}`);
    if (await realpath(piRoot) !== piRoot) throw new Error(`Workspace Pi state path is unsafe: ${piRoot}`);
    const sessionsState = await directoryState(sessionsRoot);
    if (sessionsState === "missing") return emptySessionIndex();
    if (sessionsState !== "directory") throw new Error(`Workspace Pi session path is unsafe: ${sessionsRoot}`);
    if (await realpath(sessionsRoot) !== sessionsRoot) {
      throw new Error(`Workspace Pi session path is unsafe: ${sessionsRoot}`);
    }

    const sessions = new Map<string, PersistedSession>();
    const duplicateIds = new Set<string>();
    let complete = true;
    const entries = await readdir(sessionsRoot, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile() || entry.isSymbolicLink() || !entry.name.endsWith(".jsonl")) continue;
      try {
        const header = await this.#readSessionPreview(join(sessionsRoot, entry.name));
        if (!header) {
          complete = false;
          continue;
        }
        if (header.cwd !== workspace.root) continue;
        if (sessions.has(header.id) || duplicateIds.has(header.id)) {
          sessions.delete(header.id);
          duplicateIds.add(header.id);
          complete = false;
          continue;
        }
        sessions.set(header.id, {
          id: header.id,
          filePath: join(sessionsRoot, entry.name),
          ...(header.title ? { title: header.title } : {}),
          updatedAt: header.updatedAt,
        });
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") complete = false;
      }
    }
    return { ids: new Set(sessions.keys()), sessions, complete };
  }

  async #readSessionPreview(path: string): Promise<PiSessionPreview | undefined> {
    const handle = await openSessionFile(path);
    try {
      const stat = await handle.stat({ bigint: true });
      if (!stat.isFile()) return undefined;
      const version = sessionFileVersion(stat);
      const cached = this.#previews.get(path);
      this.#previews.delete(path);
      if (cached?.version === version) {
        this.#previews.set(path, cached);
        return cached.preview;
      }
      const header = await readPiSessionHeader(handle);
      if (!header) return undefined;
      const title = await readPiSessionTitle(handle, Number(stat.size));
      const preview: PiSessionPreview = {
        ...header,
        ...(title ? { title } : {}),
        updatedAt: new Date(Number(stat.mtimeMs)).toISOString(),
      };
      if (sessionFileVersion(await handle.stat({ bigint: true })) === version) {
        this.#previews.set(path, { version, preview });
        if (this.#previews.size > MAX_CACHED_PREVIEWS) {
          this.#previews.delete(this.#previews.keys().next().value!);
        }
      }
      return preview;
    } finally {
      await handle.close();
    }
  }

  async readPersistedSessionMessages(
    workspace: RegisteredWorkspace,
    session: PersistedSession,
    request: MessagePageRequest = { limit: MAX_SNAPSHOT_MESSAGES },
  ): Promise<MessagePage> {
    validatePageRequest(request, "message");
    const graph = await this.#readPersistedSessionGraph(workspace, session, request.before ?? request.after);
    const messages = activeBranchMessages(graph.entries, graph.activeLeafId);
    const { records, ...pagination } = historyPage(messages, request);
    return {
      messages: records.map((record) => record.message),
      messageIds: records.map((record) => record.id),
      ...pagination,
    };
  }

  async readPersistedSessionTimeline(
    workspace: RegisteredWorkspace,
    session: PersistedSession,
    request: TimelinePageRequest = { limit: MAX_SNAPSHOT_MESSAGES },
  ): Promise<TimelinePage> {
    validatePageRequest(request, "timeline");
    if (request.branch !== undefined && !PI_MESSAGE_ID_PATTERN.test(request.branch)) {
      throw new HttpError(400, "invalid_timeline_branch", "Timeline branch is invalid");
    }
    const graph = await this.#readPersistedSessionGraph(workspace, session, request.before ?? request.after);
    const selectedLeafId = request.branch ?? graph.activeLeafId;
    if (request.branch !== undefined && !graph.leafIds.includes(request.branch)) {
      throw new HttpError(
        409,
        "session_timeline_branch_invalid",
        "Timeline branch is not present in this session history",
      );
    }
    const selectedEntries = activeBranchEntries(graph.entries, selectedLeafId);
    const projection = projectTimeline(selectedEntries);
    const { records, ...pagination } = historyPage(projection.items, request);
    const branches = graph.leafIds.map((leafId) => timelineBranchSummary(
      leafId,
      leafId === graph.activeLeafId,
      activeBranchEntries(graph.entries, leafId),
    ));
    return {
      items: records,
      history: timelineHistorySummary({
        ...(graph.activeLeafId ? { activeBranchId: graph.activeLeafId } : {}),
        ...(selectedLeafId ? { selectedBranchId: selectedLeafId } : {}),
        branches,
        projection,
      }),
      ...pagination,
    };
  }

  async #readPersistedSessionGraph(
    workspace: RegisteredWorkspace,
    session: PersistedSession,
    cursor?: string,
  ): Promise<PiSessionGraph> {
    const sessionsRoot = join(workspace.root, ".pi", "sessions");
    const relation = relative(sessionsRoot, session.filePath);
    if (!relation || relation.startsWith("..") || isAbsolute(relation) || relation.includes(sep)) {
      throw historyUnavailable();
    }

    let handle: FileHandle | undefined;
    const cacheKey = JSON.stringify([workspace.root, session.id, session.filePath]);
    try {
      handle = await openSessionFile(session.filePath);
      const stat = await handle.stat({ bigint: true });
      const version = sessionFileVersion(stat);
      const cached = this.#graphs.get(cacheKey);
      this.#graphs.delete(cacheKey);
      if (cached?.version === version) {
        this.#graphs.set(cacheKey, cached);
        return cached.graph;
      }
      const input = handle.createReadStream({ autoClose: false, encoding: "utf8" });
      const lines = createInterface({ input, crlfDelay: Infinity });
      const entries = new Map<string, PiSessionHistoryEntry>();
      let activeLeafId: string | undefined;
      let headerSeen = false;
      for await (const line of lines) {
        if (!line.trim()) continue;
        const record = parseJsonObject(line);
        if (!headerSeen) {
          const header = parsePiSessionRecord(record);
          if (!header || header.id !== session.id || header.cwd !== workspace.root) {
            throw historyUnavailable();
          }
          headerSeen = true;
          continue;
        }
        const entry = parsePiSessionHistoryEntry(record);
        if (entries.has(entry.id)) {
          if (cursor === entry.id) {
            throw new HttpError(
              409,
              "session_history_cursor_ambiguous",
              "History cursor occurs more than once in session history",
            );
          }
          throw historyUnavailable();
        }
        entries.set(entry.id, entry);
        activeLeafId = entry.id;
      }
      if (!headerSeen) throw historyUnavailable();
      const finalStat = await handle.stat({ bigint: true });
      if (finalStat.size > MAX_SESSION_FILE_BYTES) throw historyUnavailable();
      const unchanged = sessionFileVersion(finalStat) === version;
      const parentIds = new Set(
        [...entries.values()].flatMap((entry) => entry.parentId ? [entry.parentId] : []),
      );
      const leafIds = [...entries.keys()].filter((id) => !parentIds.has(id));
      if (leafIds.length > MAX_SESSION_BRANCHES) throw historyUnavailable();
      if (activeLeafId !== undefined && !leafIds.includes(activeLeafId)) throw historyUnavailable();
      const graph = { entries, activeLeafId, leafIds };
      const bytes = Number(finalStat.size);
      // A valid history remains readable during append, but must not be cached.
      if (unchanged && bytes <= MAX_CACHED_SESSION_BYTES) {
        this.#graphs.set(cacheKey, { version, bytes, graph });
        let totalBytes = [...this.#graphs.values()].reduce((sum, entry) => sum + entry.bytes, 0);
        while (this.#graphs.size > MAX_CACHED_SESSIONS || totalBytes > MAX_CACHED_SESSION_BYTES) {
          const oldest = this.#graphs.keys().next().value!;
          totalBytes -= this.#graphs.get(oldest)!.bytes;
          this.#graphs.delete(oldest);
        }
      }
      return graph;
    } catch (error) {
      this.#graphs.delete(cacheKey);
      if (error instanceof HttpError) throw error;
      const code = (error as NodeJS.ErrnoException).code;
      if (code === "ENOENT" || code === "ELOOP") {
        throw new HttpError(404, "session_history_not_found", "Session history no longer exists");
      }
      throw historyUnavailable();
    } finally {
      await handle?.close();
    }
  }

  async #resolvedRoot(): Promise<string> {
    const stat = await lstat(this.#configuredRoot);
    if (!stat.isDirectory() || stat.isSymbolicLink()) {
      throw new Error("TS_PHONE_WORKSPACES must be a real directory");
    }
    return realpath(this.#configuredRoot);
  }

  async #assertCurrentWorkspace(workspace: RegisteredWorkspace): Promise<void> {
    const current = await this.get(workspace.id);
    if (current.root !== workspace.root) {
      throw new HttpError(409, "workspace_changed", "Workspace path changed; refresh and try again");
    }
  }
}

function sessionFileVersion(stat: {
  dev: bigint; ino: bigint; size: bigint; mtimeNs: bigint; ctimeNs: bigint;
}): string {
  return [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs].join(":");
}

type DirectoryState = "missing" | "directory" | "unsafe";

async function directoryState(path: string): Promise<DirectoryState> {
  try {
    const stat = await lstat(path);
    return stat.isDirectory() && !stat.isSymbolicLink() ? "directory" : "unsafe";
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return "missing";
    throw error;
  }
}

interface PiSessionHeader {
  id: string;
  cwd: string;
}

interface PiSessionPreview extends PiSessionHeader {
  title?: string;
  updatedAt: string;
}

interface PiSessionHistoryEntry extends SessionTimelineEntry {}

interface PiSessionGraph {
  entries: ReadonlyMap<string, PiSessionHistoryEntry>;
  activeLeafId: string | undefined;
  leafIds: string[];
}

async function readPiSessionHeader(handle: FileHandle): Promise<PiSessionHeader | undefined> {
  const buffer = Buffer.allocUnsafe(4096);
  let pending = Buffer.alloc(0);
  let offset = 0;
  while (offset < MAX_SESSION_HEADER_BYTES) {
    const length = Math.min(buffer.length, MAX_SESSION_HEADER_BYTES - offset);
    const { bytesRead } = await handle.read(buffer, 0, length, offset);
    if (bytesRead === 0) break;
    offset += bytesRead;
    pending = Buffer.concat([pending, buffer.subarray(0, bytesRead)]);
    while (true) {
      const newline = pending.indexOf(0x0a);
      if (newline < 0) break;
      const line = pending.subarray(0, newline).toString("utf8");
      pending = pending.subarray(newline + 1);
      if (line.trim()) return parsePiSessionHeader(line);
    }
  }
  const finalLine = pending.toString("utf8");
  return finalLine.trim() ? parsePiSessionHeader(finalLine) : undefined;
}

async function readPiSessionTitle(handle: FileHandle, fileSize: number): Promise<string | undefined> {
  // A list preview never parses the full graph or includes assistant/tool content.
  const buffer = Buffer.allocUnsafe(Math.min(fileSize, MAX_SESSION_TITLE_BYTES));
  const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
  const lines = buffer.subarray(0, bytesRead).toString("utf8").split("\n");
  if (bytesRead < fileSize) lines.pop();
  for (const line of lines) {
    try {
      const record = parseJsonObject(line);
      if (record.type !== "message") continue;
      const message = record.message;
      if (!message || typeof message !== "object" || Array.isArray(message)) continue;
      const { role, content } = message as Record<string, unknown>;
      if (role !== "user") continue;
      const text = typeof content === "string" ? content : Array.isArray(content)
        ? content.flatMap((block: unknown) => {
          if (!block || typeof block !== "object") return [];
          const value = block as Record<string, unknown>;
          return value.type === "text" && typeof value.text === "string" ? [value.text] : [];
        }).join(" ") : "";
      const title = text.replace(/[\x00-\x1f\x7f\s]+/g, " ").trim();
      if (title) return Array.from(title).slice(0, 80).join("");
    } catch {
      // A partial or unsupported record must not make history disappear from lists.
    }
  }
  return undefined;
}

function parsePiSessionHeader(line: string): PiSessionHeader | undefined {
  if (!line.trim()) return undefined;
  try {
    return parsePiSessionRecord(parseJsonObject(line));
  } catch {
    return undefined;
  }
}

function parsePiSessionRecord(record: Record<string, unknown>): PiSessionHeader | undefined {
  if (record.type !== "session"
    || typeof record.id !== "string"
    || !PI_SESSION_ID_PATTERN.test(record.id)
    || typeof record.cwd !== "string"
    || !isAbsolute(record.cwd)) {
    return undefined;
  }
  return { id: record.id, cwd: resolve(record.cwd) };
}

function parsePiSessionHistoryEntry(record: Record<string, unknown>): PiSessionHistoryEntry {
  if (typeof record.type !== "string"
    || record.type === "session"
    || typeof record.id !== "string"
    || !PI_MESSAGE_ID_PATTERN.test(record.id)
    || (record.parentId !== null
      && (typeof record.parentId !== "string" || !PI_MESSAGE_ID_PATTERN.test(record.parentId)))) {
    throw historyUnavailable();
  }
  return {
    id: record.id,
    parentId: record.parentId,
    record,
  };
}

function activeBranchMessages(
  entries: ReadonlyMap<string, PiSessionHistoryEntry>,
  leafId: string | undefined,
): ProjectedMessageRecord[] {
  const messages: ProjectedMessageRecord[] = [];
  const visited = new Set<string>();
  let current = leafId === undefined ? undefined : entries.get(leafId);
  while (current) {
    if (visited.has(current.id)) throw historyUnavailable();
    visited.add(current.id);
    if (current.record.type === "message") {
      const message = projectMessage(current.record.message);
      if (message !== undefined) messages.push({ id: current.id, message });
    }
    if (current.parentId === null) break;
    current = entries.get(current.parentId);
    if (!current) throw historyUnavailable();
  }
  return messages.reverse();
}

function activeBranchEntries(
  entries: ReadonlyMap<string, PiSessionHistoryEntry>,
  leafId: string | undefined,
): PiSessionHistoryEntry[] {
  const branch: PiSessionHistoryEntry[] = [];
  const visited = new Set<string>();
  let current = leafId === undefined ? undefined : entries.get(leafId);
  while (current) {
    if (visited.has(current.id)) throw historyUnavailable();
    visited.add(current.id);
    branch.push(current);
    if (current.parentId === null) break;
    current = entries.get(current.parentId);
    if (!current) throw historyUnavailable();
  }
  return branch.reverse();
}

function validatePageRequest(request: MessagePageRequest, resource: "message" | "timeline"): void {
  if (!Number.isSafeInteger(request.limit) || request.limit < 1 || request.limit > MAX_SNAPSHOT_MESSAGES) {
    throw new HttpError(400, `invalid_${resource}_limit`, `${capitalize(resource)} page limit must be between 1 and 500`);
  }
  if ([request.before, request.after].some((cursor) => cursor !== undefined && !PI_MESSAGE_ID_PATTERN.test(cursor))) {
    throw new HttpError(400, `invalid_${resource}_cursor`, `${capitalize(resource)} cursor is invalid`);
  }
  if (request.edge !== undefined && request.edge !== "start") {
    throw new HttpError(400, `invalid_${resource}_query`, "History edge is invalid");
  }
}

function capitalize(value: string): string {
  return `${value[0]!.toUpperCase()}${value.slice(1)}`;
}

function parseJsonObject(line: string): Record<string, unknown> {
  const value = JSON.parse(line) as unknown;
  if (!value || typeof value !== "object" || Array.isArray(value)) throw historyUnavailable();
  return value as Record<string, unknown>;
}

async function openSessionFile(path: string): Promise<FileHandle> {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > MAX_SESSION_FILE_BYTES) throw historyUnavailable();
    return handle;
  } catch (error) {
    await handle.close();
    throw error;
  }
}

function emptySessionIndex(): PersistedSessionIndex {
  return { ids: new Set(), sessions: new Map(), complete: true };
}

function historyUnavailable(): HttpError {
  return new HttpError(409, "session_history_unavailable", "Session history is unavailable or unsafe");
}
