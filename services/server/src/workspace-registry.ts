import { constants } from "node:fs";
import { lstat, open, readdir, realpath, type FileHandle } from "node:fs/promises";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { createInterface } from "node:readline";
import { HttpError } from "./errors.js";
import {
  MAX_SNAPSHOT_MESSAGES,
  boundProjectedMessageRecords,
  projectMessage,
  type ProjectedMessageRecord,
} from "./message-projection.js";
import {
  boundTimelineItems,
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
}

export class WorkspaceRegistry {
  readonly #configuredRoot: string;

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
        const header = await readPiSessionHeader(join(sessionsRoot, entry.name));
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
        });
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") complete = false;
      }
    }
    return { ids: new Set(sessions.keys()), sessions, complete };
  }

  async readPersistedSessionMessages(
    workspace: RegisteredWorkspace,
    session: PersistedSession,
    request: MessagePageRequest = { limit: MAX_SNAPSHOT_MESSAGES },
  ): Promise<MessagePage> {
    validatePageRequest(request, "message");
    const graph = await this.#readPersistedSessionGraph(workspace, session, request.before);
    const messages = activeBranchMessages(graph.entries, graph.activeLeafId);
    const end = pageEnd(messages, request.before, "Message");
    const bounded = boundProjectedMessageRecords(messages.slice(0, end), request.limit);
    if (end > 0 && bounded.records.length === 0) throw historyUnavailable();
    const hasMore = bounded.omitted > 0;
    return {
      messages: bounded.records.map((record) => record.message),
      messageIds: bounded.records.map((record) => record.id),
      hasMore,
      ...(hasMore && bounded.records[0] ? { nextBefore: bounded.records[0].id } : {}),
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
    const graph = await this.#readPersistedSessionGraph(workspace, session, request.before);
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
    const end = pageEnd(projection.items, request.before, "Timeline");
    const bounded = boundTimelineItems(projection.items.slice(0, end), request.limit);
    if (end > 0 && bounded.items.length === 0) throw historyUnavailable();
    const hasMore = bounded.omitted > 0;
    const branches = graph.leafIds.map((leafId) => timelineBranchSummary(
      leafId,
      leafId === graph.activeLeafId,
      activeBranchEntries(graph.entries, leafId),
    ));
    return {
      items: bounded.items,
      history: timelineHistorySummary({
        ...(graph.activeLeafId ? { activeBranchId: graph.activeLeafId } : {}),
        ...(selectedLeafId ? { selectedBranchId: selectedLeafId } : {}),
        branches,
        projection,
      }),
      hasMore,
      ...(hasMore && bounded.items[0] ? { nextBefore: bounded.items[0].id } : {}),
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
    try {
      handle = await openSessionFile(session.filePath);
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
      if ((await handle.stat()).size > MAX_SESSION_FILE_BYTES) throw historyUnavailable();
      const parentIds = new Set(
        [...entries.values()].flatMap((entry) => entry.parentId ? [entry.parentId] : []),
      );
      const leafIds = [...entries.keys()].filter((id) => !parentIds.has(id));
      if (leafIds.length > MAX_SESSION_BRANCHES) throw historyUnavailable();
      if (activeLeafId !== undefined && !leafIds.includes(activeLeafId)) throw historyUnavailable();
      return { entries, activeLeafId, leafIds };
    } catch (error) {
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

interface PiSessionHistoryEntry extends SessionTimelineEntry {}

interface PiSessionGraph {
  entries: ReadonlyMap<string, PiSessionHistoryEntry>;
  activeLeafId: string | undefined;
  leafIds: string[];
}

async function readPiSessionHeader(path: string): Promise<PiSessionHeader | undefined> {
  const handle = await openSessionFile(path);
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) return undefined;
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
  } finally {
    await handle.close();
  }
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
  if (request.before !== undefined && !PI_MESSAGE_ID_PATTERN.test(request.before)) {
    throw new HttpError(400, `invalid_${resource}_cursor`, `${capitalize(resource)} cursor is invalid`);
  }
}

function pageEnd(records: readonly { id: string }[], before: string | undefined, resource: string): number {
  if (before === undefined) return records.length;
  const end = records.findIndex((record) => record.id === before);
  if (end < 0) {
    throw new HttpError(
      409,
      "session_history_cursor_invalid",
      `${resource} cursor is not present in this session history`,
    );
  }
  return end;
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
