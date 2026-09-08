import { spawn } from "node:child_process";
import { HttpError } from "../errors.js";
import { readLauncherError } from "./launcher-errors.js";

const MAX_REPLY_BYTES = 16 * 1024;
const PREFLIGHT_TIMEOUT_MS = 15_000;

export interface LifecyclePreflight {
  rootAgentActive: boolean;
  sessionWritersActive: boolean;
  remoteCalculations: number;
  unresolvedRemoteEffects: number;
}

export interface LifecycleGuard extends LifecyclePreflight {
  assertHeld(): void;
}

// TSPi owns lock and scientific-state inspection. The Host validates the reply
// against its own resolved workspace and retains stdin until the mutation ends.
export function runLifecycle(executable: string, workspaceId: string, workspaceRoot: string): Promise<LifecyclePreflight>;
export function runLifecycle<T>(executable: string, workspaceId: string, workspaceRoot: string, operation: (guard: LifecycleGuard) => Promise<T>): Promise<T>;
export async function runLifecycle<T>(
  executable: string,
  workspaceId: string,
  workspaceRoot: string,
  operation?: (guard: LifecycleGuard) => Promise<T>,
): Promise<T | LifecyclePreflight> {
  const guarded = operation !== undefined;
  const child = spawn(executable, [
    "--workspace", workspaceId,
    guarded ? "--lifecycle-guard" : "--lifecycle-preflight",
  ], { env: process.env, stdio: ["pipe", "pipe", "pipe"] });
  let reply = Buffer.alloc(0);
  let diagnostic = "";
  let ended = false;
  let resolveExit!: () => void;
  const exit = new Promise<void>((resolve) => { resolveExit = resolve; });
  child.on("error", () => { ended = true; resolveExit(); });
  child.on("close", () => { ended = true; resolveExit(); });
  child.stdin.on("error", () => { /* Exit/held checks surface lost guards. */ });
  child.stderr.on("data", (chunk: Buffer) => {
    diagnostic = (diagnostic + chunk.toString("utf8")).slice(-MAX_REPLY_BYTES);
  });
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const raw = await new Promise<unknown>((resolve, reject) => {
      timer = setTimeout(() => reject(unavailable("Workspace preflight timed out")), PREFLIGHT_TIMEOUT_MS);
      child.once("error", reject);
      child.once("close", (code) => {
        if (code !== 0) {
          reject(readLauncherError(diagnostic) ?? unavailable("Workspace preflight failed; inspect Host diagnostics"));
        } else if (!guarded) {
          parse();
        } else {
          reject(unavailable("Workspace lifecycle guard exited before acknowledgement"));
        }
      });
      function parse(): void {
        try { resolve(JSON.parse(reply.toString("utf8"))); }
        catch { reject(unavailable("Workspace preflight returned invalid data")); }
      }
      child.stdout.on("data", (chunk: Buffer) => {
        if (reply.length + chunk.length > MAX_REPLY_BYTES) {
          reject(unavailable("Workspace preflight reply is too large"));
          child.kill("SIGKILL");
          return;
        }
        reply = Buffer.concat([reply, chunk]);
        if (guarded && reply.includes(10)) parse();
      });
    });
    clearTimeout(timer);
    const value = parsePreflight(raw, workspaceRoot, guarded);
    if (!operation) return value;
    if (value.rootAgentActive || value.sessionWritersActive) {
      throw new HttpError(409, "workspace_delete_blocked", "Stop workspace conversation writers before deleting its data");
    }
    const assertHeld = (): void => {
      if (ended || child.exitCode !== null || child.signalCode !== null) {
        throw unavailable("Workspace lifecycle guard was lost");
      }
    };
    assertHeld();
    return await operation({ ...value, assertHeld });
  } finally {
    clearTimeout(timer);
    child.stdin.end();
    // The successful guard exits on EOF. Failed/blocked preflights must also
    // be reaped; a bounded fallback handles a broken launcher.
    const killTimer = setTimeout(() => child.kill("SIGKILL"), 1_000);
    await exit;
    clearTimeout(killTimer);
  }
}

function parsePreflight(raw: unknown, workspaceRoot: string, guarded: boolean): LifecyclePreflight {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw unavailable("Invalid workspace preflight");
  const value = raw as Record<string, unknown>;
  if (value.schema_version !== (guarded ? "ts-phone-project-guard/1" : "ts-phone-project-preflight/2")
    || value.workspace_root !== workspaceRoot
    || typeof value.root_agent_active !== "boolean"
    || value.session_guard_contract !== "tspi-session-guard/1"
    || typeof value.session_writers_active !== "boolean"
    || !count(value.remote_calculations)
    || !count(value.unresolved_remote_effects)
    || (guarded && value.guard_acquired !== !(value.root_agent_active || value.session_writers_active))) {
    throw unavailable("Workspace preflight returned invalid or incorrectly bound data");
  }
  return {
    rootAgentActive: value.root_agent_active,
    sessionWritersActive: value.session_writers_active,
    remoteCalculations: value.remote_calculations,
    unresolvedRemoteEffects: value.unresolved_remote_effects,
  };
}

function count(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function unavailable(message: string): HttpError {
  return new HttpError(503, "workspace_preflight_unavailable", message);
}
