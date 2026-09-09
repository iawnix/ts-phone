import { execFile, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { promisify } from "node:util";
import { constants } from "node:fs";
import { access, lstat, realpath } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { HttpError } from "../errors.js";
import type { SessionAccessMode } from "../types.js";
import { runLifecycle, type LifecycleGuard, type LifecyclePreflight } from "./lifecycle-client.js";
import { WorkerRpc } from "./worker-rpc.js";
import { parseModelCatalog } from "./model-catalog.js";
import type { PhoneModel } from "../types.js";
import { readLauncherError } from "./launcher-errors.js";

const MAX_DIAGNOSTIC_BYTES = 16 * 1024;

export interface WorkerStartRequest {
  workspaceId: string;
  sessionId: string;
  accessMode: SessionAccessMode;
  launchId?: string;
  name?: string;
  model?: string;
}

export interface WorkerExit {
  code: number | null;
  signal: NodeJS.Signals | null;
  diagnostic: string;
  startupError?: HttpError;
}

export interface WorkerLaunch {
  exit: Promise<WorkerExit>;
}

interface WorkerRecord {
  request: WorkerStartRequest;
  child: ChildProcessWithoutNullStreams;
  exit: Promise<WorkerExit>;
  stderr: BoundedText;
  rpc: WorkerRpc;
}

interface PendingWorkerStart {
  request: WorkerStartRequest;
  result: Promise<WorkerLaunch>;
}

export class WorkerSupervisor {
  readonly #tspiPath: string | undefined;
  readonly #shutdownTimeoutMs: number;
  readonly #bridgeSocketPath: string;
  readonly #bridgeSecretPath: string;
  readonly #workers = new Map<string, WorkerRecord>();
  // A capability probe and process spawn both await external work. Keep the
  // admission promise visible so two clients cannot pass those awaits and
  // launch two Workers for the same session.
  readonly #starting = new Map<string, PendingWorkerStart>();
  #closing = false;
  onRuntimeError: ((request: WorkerStartRequest, error: HttpError) => void) | undefined;

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

  request(workspaceId: string, sessionId: string): WorkerStartRequest | undefined {
    const request = this.#workers.get(workerKey(workspaceId, sessionId))?.request;
    return request ? { ...request } : undefined;
  }

  async checkCompatibility(): Promise<void> {
    await this.#checkGuardContract(await this.#executable());
  }

  async verifyWriter(workspaceId: string, workspaceRoot: string, sessionId: string,
    accessMode: SessionAccessMode, pid: number): Promise<void> {
    // A bridge-only deployment cannot launch or delete sessions. With Session
    // Host configured, every admitted writer must prove the launcher's guards.
    if (!this.available) return;
    const owned = this.#workers.get(workerKey(workspaceId, sessionId));
    if (owned && owned.child.pid !== pid) {
      throw new HttpError(409, "session_writer_unverified", "The Bridge PID does not match the Host-managed Worker");
    }
    try {
      const { stdout } = await promisify(execFile)(await this.#executable(), [
        "--session-writer-check", "--workspace", workspaceId,
        "--session-id", sessionId, "--phone-access", accessMode, "--writer-pid", String(pid),
      ], { timeout: 10_000, maxBuffer: 4096 });
      const value = JSON.parse(stdout);
      if (value.session_guard_contract === "tspi-session-guard/1" && value.verified === true
        && value.workspace_root === workspaceRoot && value.session_id === sessionId
        && value.access_mode === accessMode && value.pid === pid) return;
    } catch (error) {
      const failure = readLauncherError(error instanceof Error && "stderr" in error ? error.stderr : undefined);
      if (failure) throw failure;
    }
    throw new HttpError(409, "session_writer_unverified", "The Host could not verify this conversation's process identity and writer guards");
  }

  async start(request: WorkerStartRequest): Promise<WorkerLaunch> {
    const key = workerKey(request.workspaceId, request.sessionId);
    const existing = this.#workers.get(key);
    if (existing) {
      if (!sameWorkerStartRequest(existing.request, request)) {
        throw new HttpError(409, "worker_identity_conflict", "A different TSPi runtime already owns this conversation");
      }
      return { exit: existing.exit };
    }
    const pending = this.#starting.get(key);
    if (pending) {
      if (!sameWorkerStartRequest(pending.request, request)) {
        throw new HttpError(409, "worker_identity_conflict", "A different TSPi runtime is already starting this conversation");
      }
      return pending.result;
    }
    let result: Promise<WorkerLaunch>;
    result = this.#startOnce(request).finally(() => {
      if (this.#starting.get(key)?.result === result) this.#starting.delete(key);
    });
    this.#starting.set(key, { request: { ...request }, result });
    return result;
  }

  async #startOnce(request: WorkerStartRequest): Promise<WorkerLaunch> {
    const executable = await this.#executable();
    await this.#checkGuardContract(executable);
    if (this.#closing) throw new HttpError(503, "host_stopping", "TSPi Host is stopping");
    const key = workerKey(request.workspaceId, request.sessionId);
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
        TS_PHONE_LAUNCH_ID: request.launchId ?? "",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    const stderr = new BoundedText(MAX_DIAGNOSTIC_BYTES);
    const rpc = new WorkerRpc(child.stdin, child.stdout, (error) => this.onRuntimeError?.(request, error));
    child.stderr.on("data", (chunk: Buffer | string) => stderr.append(chunk));
    const exit = new Promise<WorkerExit>((resolve) => {
      child.once("error", (error) => {
        rpc.close();
        if (this.#workers.get(key)?.child === child) this.#workers.delete(key);
        resolve({ code: null, signal: null, diagnostic: error.message });
      });
      // close follows stdio drain; exit alone can lose the final error record.
      child.once("close", (code, signal) => {
        rpc.close();
        if (this.#workers.get(key)?.child === child) this.#workers.delete(key);
        const startupError = readLauncherError(stderr.value);
        resolve({ code, signal, diagnostic: stderr.value, ...(startupError ? { startupError } : {}) });
      });
    });
    this.#workers.set(key, { request: { ...request }, child, exit, stderr, rpc });
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
    const killed = await Promise.race([
      record.exit.then(() => true),
      delay(this.#shutdownTimeoutMs).then(() => false),
    ]);
    if (!killed) throw new HttpError(409, "worker_cleanup_uncertain", "TSPi process exit could not be confirmed");
  }

  async prompt(workspaceId: string, sessionId: string, message: string, followUp: boolean): Promise<void> {
    const worker = this.#workers.get(workerKey(workspaceId, sessionId));
    if (!worker) throw new HttpError(409, "session_offline", "TSPi Worker is offline");
    await worker.rpc.prompt(message, followUp);
  }

  async models(): Promise<PhoneModel[]> {
    const executable = await this.#executable();
    try {
      const { stdout } = await promisify(execFile)(executable, ["--phone-models"], {
        timeout: 10_000, maxBuffer: 1024 * 1024,
      });
      return parseModelCatalog(JSON.parse(stdout));
    } catch {
      throw new HttpError(503, "model_check_failed", "The Host could not read its Pi model catalog");
    }
  }

  async setModel(workspaceId: string, sessionId: string, provider: string, modelId: string): Promise<PhoneModel> {
    const worker = this.#workers.get(workerKey(workspaceId, sessionId));
    if (!worker) throw new HttpError(409, "model_control_unavailable", "Model selection needs a Host-managed conversation");
    const result = await worker.rpc.setModel(provider, modelId);
    if (!result || typeof result !== "object" || !("provider" in result) || !("id" in result)
      || result.provider !== provider || result.id !== modelId) {
      throw new HttpError(409, "model_change_unconfirmed", "Pi did not confirm the selected model; refresh before sending");
    }
    return parseModelCatalog({ schemaVersion: "ts-phone-models/1", models: [result] })[0]!;
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
    this.#closing = true;
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
    // TSPi derives its installation root from the invoked launcher location.
    // Validate the target, but preserve the stable installation symlink.
    return path;
  }

  async #checkGuardContract(executable: string): Promise<void> {
    try {
      const { stdout } = await promisify(execFile)(executable, ["--session-host-capabilities"], {
        timeout: 10_000, maxBuffer: 4096,
      });
      if (JSON.parse(stdout).session_guard_contract === "tspi-session-guard/1") return;
    } catch (error) {
      const failure = readLauncherError(error instanceof Error && "stderr" in error ? error.stderr : undefined);
      if (failure) throw failure;
    }
    throw new HttpError(409, "session_guard_upgrade_required", "Update the installed TSPi launcher before activating conversations");
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

function sameWorkerStartRequest(left: WorkerStartRequest, right: WorkerStartRequest): boolean {
  return left.workspaceId === right.workspaceId
    && left.sessionId === right.sessionId
    && left.accessMode === right.accessMode
    && left.launchId === right.launchId
    && left.name === right.name
    && left.model === right.model;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
