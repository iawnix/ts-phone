import { createHash, randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { open, rename, rm } from "node:fs/promises";
import { join } from "node:path";
import { HttpError, RuntimeError } from "../errors.js";
import type { CommandReceipt, CommandStatus, PromptInput } from "../types.js";

const FILE = "commands.json";
const SCHEMA = "ts-phone-commands/1";
const MAX_BYTES = 16 * 1024 * 1024;
const MAX_RECEIPTS = 10_000;
const unfinished = new Set<CommandStatus>(["queued", "starting", "running", "unknown"]);

export interface QueuedCommand extends CommandReceipt {
  workspaceId: string;
  sessionId: string;
  digest: string;
  message?: string;
  model?: string;
  clientKind: "phone" | "terminal";
}

interface QueueHooks {
  ready(command: QueuedCommand): boolean;
  dispatch(command: QueuedCommand): Promise<void>;
  changed(workspaceId: string): void;
}

export type CommandOutcome =
  | { status: "completed" | "cancelled" }
  | { status: "failed"; problem: string };

/** Older bridges can report quiescence without certifying a final output. */
export function commandOutcome(payload: unknown): CommandOutcome {
  const value = (payload as { outcome?: unknown } | null)?.outcome;
  if (!value || typeof value !== "object") return { status: "failed", problem: "generation_unconfirmed" };
  const outcome = value as Record<string, unknown>;
  if (outcome.status === "completed" || outcome.status === "cancelled") return { status: outcome.status };
  const problems = ["provider_unavailable", "provider_rate_limited", "provider_auth_failed", "provider_error", "generation_incomplete"];
  return { status: "failed", problem: typeof outcome.problem === "string" && problems.includes(outcome.problem)
    ? outcome.problem : "generation_unconfirmed" };
}

/** A workspace lane is held until agent_settled, not just the RPC acknowledgement. */
export class CommandQueue {
  #commands: QueuedCommand[];
  #tail: Promise<unknown> = Promise.resolve();
  readonly #draining = new Map<string, Promise<void>>();
  readonly #wakeAgain = new Set<string>();
  #hooks?: QueueHooks;
  #closed = false;
  #faulted = false;

  private constructor(readonly stateDir: string, commands: QueuedCommand[]) {
    this.#commands = commands;
  }

  static async open(stateDir: string): Promise<CommandQueue> {
    let commands: QueuedCommand[] = [];
    let handle;
    try {
      handle = await open(join(stateDir, FILE), constants.O_RDONLY | constants.O_NOFOLLOW);
      const stat = await handle.stat();
      if (!stat.isFile() || stat.size > MAX_BYTES || (stat.mode & 0o077) !== 0
        || (process.getuid && stat.uid !== process.getuid())) throw new Error("Unsafe Host command store");
      commands = parseCommands(JSON.parse(await handle.readFile("utf8")));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    } finally { await handle?.close(); }
    const queue = new CommandQueue(stateDir, commands);
    if (commands.some((c) => c.status === "starting" || c.status === "running")) {
      await queue.#mutate((next) => {
        for (const c of next) {
          if (c.status === "starting" || c.status === "running") update(c, "unknown", "host_restarted");
        }
      });
    }
    return queue;
  }

  connect(hooks: QueueHooks): void { this.#hooks = hooks; }
  get faulted(): boolean { return this.#faulted; }
  workspaceIds(): string[] { return [...new Set(this.#commands.filter((c) => unfinished.has(c.status)).map((c) => c.workspaceId))]; }

  find(workspaceId: string, sessionId: string, id: string): QueuedCommand | undefined {
    const c = this.#commands.find((c) => c.workspaceId === workspaceId && c.sessionId === sessionId && c.clientMessageId === id);
    return c ? { ...c } : undefined;
  }

  hasPending(workspaceId: string, sessionId?: string): boolean {
    return this.pendingCount(workspaceId, sessionId) > 0;
  }

  pendingCount(workspaceId: string, sessionId?: string): number {
    return this.#commands.filter((c) => c.workspaceId === workspaceId
      && (sessionId === undefined || c.sessionId === sessionId) && unfinished.has(c.status)).length;
  }

  hasUnknown(workspaceId: string): boolean {
    return this.#commands.some((c) => c.workspaceId === workspaceId && c.status === "unknown");
  }

  view(workspaceId: string, sessionId: string): CommandReceipt[] {
    const pending = this.#commands.filter((c) => c.workspaceId === workspaceId && unfinished.has(c.status));
    const failures = this.#commands.filter((c) => c.workspaceId === workspaceId && c.sessionId === sessionId && c.status === "failed").slice(-3);
    return [...pending, ...failures].map((c) => ({
      ...receipt(c),
      sessionId: c.sessionId,
      ...(c.status === "queued" ? { position: pending.indexOf(c) + 1 } : {}),
      ...(c.preview ? { preview: c.preview } : {}),
    }));
  }

  async enqueue(workspaceId: string, sessionId: string, input: PromptInput, model?: string): Promise<CommandReceipt> {
    const result = await this.#mutate((next) => {
      const existing = next.find((c) => c.workspaceId === workspaceId && c.sessionId === sessionId && c.clientMessageId === input.clientMessageId);
      const digest = commandDigest(input.message);
      if (existing) {
        if (existing.digest !== digest) throw new HttpError(409, "message_id_conflict", "Message identity was reused with different content");
        return receipt(existing);
      }
      if (next.length >= MAX_RECEIPTS) throw new HttpError(409, "queue_capacity_exceeded", "Host command receipt storage is full");
      if (next.filter((c) => c.workspaceId === workspaceId && unfinished.has(c.status)).length >= 32) {
        throw new HttpError(409, "queue_capacity_exceeded", "This workspace already has 32 unfinished requests");
      }
      const now = new Date().toISOString();
      const command: QueuedCommand = {
        workspaceId, sessionId, clientMessageId: input.clientMessageId, digest,
        status: "queued", createdAt: now, updatedAt: now, message: input.message, preview: input.message.slice(0, 240),
        clientKind: input.clientKind ?? "phone", ...(model ? { model } : {}),
      };
      next.push(command);
      return receipt(command);
    });
    this.#hooks?.changed(workspaceId);
    this.wake(workspaceId);
    return result;
  }

  /**
   * Move only commands that have not started to a newly selected model.
   *
   * A queued command is still an intent, so changing the next-turn model
   * should change the model that will actually receive that intent. Once a
   * command has started, its model is part of the execution record and must
   * remain immutable for auditability.
   */
  async retargetQueued(workspaceId: string, sessionId: string, model: string): Promise<number> {
    const changed = await this.#mutate((next) => {
      let count = 0;
      for (const command of next) {
        if (command.workspaceId !== workspaceId || command.sessionId !== sessionId || command.status !== "queued") continue;
        if (command.model === model) continue;
        command.model = model;
        command.updatedAt = new Date().toISOString();
        count += 1;
      }
      return count;
    });
    if (changed > 0) this.#hooks?.changed(workspaceId);
    return changed;
  }

  async cancel(workspaceId: string, sessionId: string, id: string): Promise<CommandReceipt> {
    const result = await this.#mutate((next) => {
      const command = requireCommand(next, workspaceId, sessionId, id);
      if (command.status !== "queued" && command.status !== "cancelled") {
        throw new HttpError(409, "command_already_started", "This request has already left the queue; cancelling it would not stop execution");
      }
      update(command, "cancelled");
      return receipt(command);
    });
    this.#hooks?.changed(workspaceId);
    this.wake(workspaceId);
    return result;
  }

  async acknowledge(workspaceId: string, sessionId: string, id: string): Promise<CommandReceipt> {
    const result = await this.#mutate((next) => {
      const command = requireCommand(next, workspaceId, sessionId, id);
      if (command.status !== "unknown" && command.status !== "acknowledged") {
        throw new HttpError(409, "command_not_unknown", "Only an uncertain execution can be acknowledged");
      }
      // Acknowledgement unblocks the lane. It does not certify completion or replay the command.
      update(command, "acknowledged", command.problem);
      return receipt(command);
    });
    this.#hooks?.changed(workspaceId);
    this.wake(workspaceId);
    return result;
  }

  async withPurgedReceipts(workspaceId: string, sessionId: string | undefined, remove: () => Promise<void>): Promise<void> {
    const removed = await this.#mutate((next) => {
      const matches = (c: QueuedCommand) => c.workspaceId === workspaceId
        && (sessionId === undefined || c.sessionId === sessionId);
      const selected = next.filter(matches);
      if (selected.some((c) => unfinished.has(c.status))) {
        throw new HttpError(409, "queue_requests_active", "Unfinished requests prevent permanent deletion");
      }
      for (let i = next.length - 1; i >= 0; i--) if (matches(next[i]!)) next.splice(i, 1);
      return selected;
    });
    try {
      await remove();
    } catch (error) {
      // Keep delivery deduplication if the enclosing resource deletion is rolled back.
      try { await this.#mutate((next) => { next.unshift(...removed); }); }
      catch {
        throw new RuntimeError("purge_recovery_failed", "Permanent deletion failed and command receipts could not be restored; inspect Host state before retrying");
      }
      throw error;
    }
  }

  settle(workspaceId: string, sessionId: string, commandId: string, outcome: CommandOutcome): void {
    this.#transitionActive(workspaceId, sessionId, outcome.status,
      outcome.status === "failed" ? outcome.problem : undefined, commandId);
  }

  disconnected(workspaceId: string, sessionId: string): void {
    this.#transitionActive(workspaceId, sessionId, "unknown", "command_ambiguous");
  }

  #transitionActive(workspaceId: string, sessionId: string, status: CommandStatus, problem?: string, commandId?: string): void {
    const active = this.#commands.find((c) => c.workspaceId === workspaceId && c.sessionId === sessionId
      && (commandId === undefined || c.clientMessageId === commandId)
      && (c.status === "starting" || c.status === "running"));
    if (!active) return;
    void this.#mutate((next) => {
      const current = requireCommand(next, workspaceId, sessionId, active.clientMessageId);
      if (current.status === "starting" || current.status === "running") update(current, status, problem);
    }).then(() => {
      this.#hooks?.changed(workspaceId);
      this.wake(workspaceId);
    }).catch(() => this.#storageFailed(workspaceId));
  }

  wake(workspaceId: string): void {
    if (this.#closed || this.#faulted || !this.#hooks) return;
    if (this.#draining.has(workspaceId)) { this.#wakeAgain.add(workspaceId); return; }
    const draining = this.#drain(workspaceId).catch(() => this.#storageFailed(workspaceId)).finally(() => {
      this.#draining.delete(workspaceId);
      if (this.#wakeAgain.delete(workspaceId)) this.wake(workspaceId);
    });
    this.#draining.set(workspaceId, draining);
  }

  async #drain(workspaceId: string): Promise<void> {
    while (!this.#closed && !this.#faulted) {
      const lane = this.#commands.filter((c) => c.workspaceId === workspaceId && unfinished.has(c.status));
      if (lane.some((c) => c.status !== "queued")) return;
      const command = lane[0];
      if (!command || !this.#hooks!.ready(command)) return;
      const started = await this.#mutate((next) => {
        const current = requireCommand(next, workspaceId, command.sessionId, command.clientMessageId);
        if (current.status !== "queued" || this.#closed || !this.#hooks!.ready(current)) return undefined;
        update(current, "starting");
        // Dispatch exactly the record frozen by this transition. A queued
        // model change may have replaced the earlier lane snapshot.
        return { ...current };
      });
      if (!started) continue;
      this.#hooks!.changed(workspaceId);
      try {
        await this.#hooks!.dispatch(started);
        await this.#mutate((next) => {
          const current = requireCommand(next, workspaceId, command.sessionId, command.clientMessageId);
          if (current.status === "starting") update(current, "running");
        });
      } catch (error) {
        const known = error instanceof HttpError;
        const problem = known || error instanceof RuntimeError ? error.code : "command_ambiguous";
        await this.#mutate((next) => {
          const current = requireCommand(next, workspaceId, command.sessionId, command.clientMessageId);
          if (current.status === "starting" || current.status === "running") {
            update(current, known && !["model_change_unconfirmed", "worker_cleanup_uncertain"].includes(problem)
              ? "failed" : "unknown", problem);
          }
        });
      }
      this.#hooks!.changed(workspaceId);
    }
  }

  async close(): Promise<void> {
    this.#closed = true;
    await Promise.allSettled(this.#draining.values());
    await this.#tail;
  }

  #storageFailed(workspaceId: string): void {
    this.#faulted = true;
    this.#hooks?.changed(workspaceId);
  }

  async #mutate<T>(operation: (next: QueuedCommand[]) => T): Promise<T> {
    const run = this.#tail.then(async () => {
      if (this.#faulted) throw new HttpError(503, "queue_storage_unavailable", "Host command storage requires recovery");
      const next = this.#commands.map((c) => ({ ...c }));
      const result = operation(next);
      const serialized = JSON.stringify({ schemaVersion: SCHEMA, commands: next });
      if (Buffer.byteLength(serialized) > MAX_BYTES) throw new HttpError(409, "queue_capacity_exceeded", "Host command storage is full");
      try { await writeCommands(this.stateDir, serialized); }
      catch {
        this.#faulted = true;
        for (const id of new Set(next.map((c) => c.workspaceId))) this.#hooks?.changed(id);
        throw new HttpError(503, "queue_storage_unavailable", "Host could not confirm command storage");
      }
      this.#commands = next;
      return result;
    });
    this.#tail = run.catch(() => {});
    return run;
  }
}

export function commandDigest(message: string): string { return createHash("sha256").update(message).digest("hex"); }

export function receipt(command: QueuedCommand): CommandReceipt {
  const { clientMessageId, status, createdAt, updatedAt, model, problem } = command;
  return { clientMessageId, status, createdAt, updatedAt, ...(model ? { model } : {}), ...(problem ? { problem } : {}) };
}

function update(command: QueuedCommand, status: CommandStatus, problem?: string): void {
  command.status = status;
  command.updatedAt = new Date().toISOString();
  if (problem) command.problem = problem;
  else delete command.problem;
  if (!unfinished.has(status)) delete command.message;
}

function requireCommand(commands: QueuedCommand[], workspaceId: string, sessionId: string, id: string): QueuedCommand {
  const c = commands.find((c) => c.workspaceId === workspaceId && c.sessionId === sessionId && c.clientMessageId === id);
  if (!c) throw new HttpError(404, "command_not_found", "Host command receipt was not found");
  return c;
}

async function writeCommands(stateDir: string, serialized: string): Promise<void> {
  const temporary = join(stateDir, `.commands.${randomUUID()}.tmp`);
  try {
    const handle = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
    try { await handle.writeFile(serialized, "utf8"); await handle.sync(); }
    finally { await handle.close(); }
    await rename(temporary, join(stateDir, FILE));
    const directory = await open(stateDir, constants.O_RDONLY);
    try { await directory.sync(); } finally { await directory.close(); }
  } finally { await rm(temporary, { force: true }); }
}

function parseCommands(value: unknown): QueuedCommand[] {
  if (!value || typeof value !== "object" || Array.isArray(value)
    || Object.keys(value).some((key) => !["schemaVersion", "commands"].includes(key))
    || !("schemaVersion" in value) || value.schemaVersion !== SCHEMA
    || !("commands" in value) || !Array.isArray(value.commands) || value.commands.length > MAX_RECEIPTS) {
    throw new Error("Invalid Host command store");
  }
  const ids = new Set<string>();
  const activeWorkspaces = new Set<string>();
  return value.commands.map((row: unknown) => {
    if (!row || typeof row !== "object" || Array.isArray(row)
      || Object.keys(row).some((key) => !["workspaceId", "sessionId", "clientMessageId", "digest",
        "status", "createdAt", "updatedAt", "message", "preview", "clientKind", "model", "problem"].includes(key))) {
      throw new Error("Invalid Host command");
    }
    const c = row as QueuedCommand;
    if (typeof c.workspaceId !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(c.workspaceId)
      || typeof c.sessionId !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$/.test(c.sessionId)
      || typeof c.clientMessageId !== "string" || !/^[A-Za-z0-9._:-]{1,160}$/.test(c.clientMessageId)
      || typeof c.digest !== "string" || !/^[a-f0-9]{64}$/.test(c.digest)
      || !["queued", "starting", "running", "completed", "failed", "cancelled", "unknown", "acknowledged"].includes(c.status)
      || typeof c.createdAt !== "string" || !Number.isFinite(Date.parse(c.createdAt))
      || typeof c.updatedAt !== "string" || !Number.isFinite(Date.parse(c.updatedAt))
      || (c.clientKind !== "phone" && c.clientKind !== "terminal")
      || (c.model !== undefined && (typeof c.model !== "string" || !/^[^\s\x00-\x1f]{1,401}$/.test(c.model)))
      || (c.problem !== undefined && (typeof c.problem !== "string" || !/^[a-z_]{1,80}$/.test(c.problem)))
      || (c.preview !== undefined && (typeof c.preview !== "string" || c.preview.length > 240))
      || (!unfinished.has(c.status) && c.message !== undefined)
      || (unfinished.has(c.status) && (typeof c.message !== "string" || c.message.length < 1 || c.message.length > 65536
        || commandDigest(c.message) !== c.digest))) throw new Error("Invalid Host command");
    if (unfinished.has(c.status) && c.status !== "queued") {
      if (activeWorkspaces.has(c.workspaceId)) throw new Error("Multiple active commands in one workspace");
      activeWorkspaces.add(c.workspaceId);
    }
    const key = JSON.stringify([c.workspaceId, c.sessionId, c.clientMessageId]);
    if (ids.has(key)) throw new Error("Duplicate Host command identity");
    ids.add(key);
    return { ...c };
  });
}
