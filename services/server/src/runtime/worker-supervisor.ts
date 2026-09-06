import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { constants } from "node:fs";
import { access, lstat, realpath } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { HttpError } from "../errors.js";
import type { SessionAccessMode } from "../types.js";
import { runLifecycle, type LifecycleGuard, type LifecyclePreflight } from "./lifecycle-client.js";

const MAX_DIAGNOSTIC_BYTES = 16 * 1024;

export interface WorkerStartRequest {
  workspaceId: string;
  sessionId: string;
  accessMode: SessionAccessMode;
  name?: string;
  model?: string;
}

export interface WorkerExit {
  code: number | null;
  signal: NodeJS.Signals | null;
  diagnostic: string;
}

export interface WorkerLaunch {
  exit: Promise<WorkerExit>;
}

interface WorkerRecord {
  child: ChildProcessWithoutNullStreams;
  exit: Promise<WorkerExit>;
  stderr: BoundedText;
}

export class WorkerSupervisor {
  readonly #tspiPath: string | undefined;
  readonly #shutdownTimeoutMs: number;
  readonly #bridgeSocketPath: string;
  readonly #bridgeSecretPath: string;
  readonly #workers = new Map<string, WorkerRecord>();

  constructor(
    tspiPath: string | undefined,
    shutdownTimeoutMs: number,
    bridgeSocketPath: string,
    bridgeSecretPath: string,
  ) {
    this.#tspiPath = tspiPath;
    this.#shutdownTimeoutMs = shutdownTimeoutMs;
    this.#bridgeSocketPath = bridgeSocketPath;
    this.#bridgeSecretPath = bridgeSecretPath;
  }

  get available(): boolean {
    return this.#tspiPath !== undefined;
  }

  owns(workspaceId: string, sessionId: string): boolean {
    return this.#workers.has(workerKey(workspaceId, sessionId));
  }

  async start(request: WorkerStartRequest): Promise<WorkerLaunch> {
    const key = workerKey(request.workspaceId, request.sessionId);
    const existing = this.#workers.get(key);
    if (existing) return { exit: existing.exit };
    const executable = await this.#executable();
    const arguments_ = [
      "--workspace", request.workspaceId,
      "--phone-worker",
      "--session-id", request.sessionId,
      "--phone-access", request.accessMode,
    ];
    if (request.name) arguments_.push("--name", request.name);
    if (request.model) arguments_.push("--model", request.model);
    const child = spawn(executable, arguments_, {
      env: {
        ...process.env,
        TS_PHONE_BRIDGE_SOCKET: this.#bridgeSocketPath,
        TS_PHONE_BRIDGE_SECRET_FILE: this.#bridgeSecretPath,
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    const stderr = new BoundedText(MAX_DIAGNOSTIC_BYTES);
    child.stdout.resume();
    child.stderr.on("data", (chunk: Buffer | string) => stderr.append(chunk));
    const exit = new Promise<WorkerExit>((resolve) => {
      child.once("error", (error) => {
        this.#workers.delete(key);
        resolve({ code: null, signal: null, diagnostic: error.message });
      });
      child.once("exit", (code, signal) => {
        this.#workers.delete(key);
        resolve({ code, signal, diagnostic: stderr.value });
      });
    });
    this.#workers.set(key, { child, exit, stderr });
    await new Promise<void>((resolve, reject) => {
      child.once("spawn", resolve);
      child.once("error", reject);
    });
    return { exit };
  }

  async stop(workspaceId: string, sessionId: string): Promise<void> {
    const record = this.#workers.get(workerKey(workspaceId, sessionId));
    if (!record) return;
    record.child.kill("SIGTERM");
    const settled = await Promise.race([
      record.exit.then(() => true),
      delay(this.#shutdownTimeoutMs).then(() => false),
    ]);
    if (settled) return;
    record.child.kill("SIGKILL");
    await record.exit;
  }

  async inspect(workspaceId: string, workspaceRoot: string): Promise<LifecyclePreflight> {
    return runLifecycle(await this.#executable(), workspaceId, workspaceRoot);
  }

  async withLifecycleGuard<T>(
    workspaceId: string,
    workspaceRoot: string,
    operation: (guard: LifecycleGuard) => Promise<T>,
  ): Promise<T> {
    return runLifecycle(await this.#executable(), workspaceId, workspaceRoot, operation);
  }

  async close(): Promise<void> {
    const keys = [...this.#workers.keys()];
    await Promise.all(keys.map((key) => {
      const [workspaceId, sessionId] = key.split("\u0000", 2) as [string, string];
      return this.stop(workspaceId, sessionId);
    }));
  }

  async #executable(): Promise<string> {
    const path = this.#tspiPath;
    if (!path) {
      throw new HttpError(503, "worker_unavailable", "This TS Phone Host is not configured to start TSPi Workers");
    }
    if (!isAbsolute(path)) throw new Error("TS_PHONE_TSPI must be an absolute path");
    const target = await realpath(path);
    const stat = await lstat(target);
    await access(target, constants.X_OK);
    if (!stat.isFile()) throw new Error("TS_PHONE_TSPI must resolve to an executable file");
    return target;
  }
}

class BoundedText {
  readonly #maxBytes: number;
  #value = Buffer.alloc(0);

  constructor(maxBytes: number) {
    this.#maxBytes = maxBytes;
  }

  append(chunk: Buffer | string): void {
    const incoming = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    this.#value = Buffer.concat([this.#value, incoming]).subarray(-this.#maxBytes);
  }

  get value(): string {
    return this.#value.toString("utf8");
  }
}

function workerKey(workspaceId: string, sessionId: string): string {
  return `${workspaceId}\u0000${sessionId}`;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
