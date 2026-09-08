import { isAbsolute, join, resolve } from "node:path";

export interface ServerConfig {
  host: string;
  port: number;
  workspaceRoot: string;
  stateDir: string;
  tspiPath: string | undefined;
  bridgeSocketPath: string;
  bridgeSecretPath: string;
  commandTimeoutMs: number;
  shutdownTimeoutMs: number;
  bridgeHeartbeatTimeoutMs: number;
  bridgeMaxRecordBytes: number;
  maxBodyBytes: number;
  eventJournalSize: number;
  eventJournalMaxBytes: number;
}

function positiveInteger(value: string | undefined, fallback: number, name: string): number {
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

function absolutePath(value: string, name: string): string {
  if (!isAbsolute(value)) throw new Error(`${name} must be an absolute path`);
  return resolve(value);
}

function loopbackHost(value: string | undefined): string {
  const host = value || "127.0.0.1";
  if (host !== "127.0.0.1" && host !== "::1") {
    throw new Error("TS_PHONE_HOST must be 127.0.0.1 or ::1");
  }
  return host;
}

export function resolveConfig(
  env: NodeJS.ProcessEnv = process.env,
  cwd = process.cwd(),
): ServerConfig {
  const port = positiveInteger(env.TS_PHONE_PORT, 22113, "TS_PHONE_PORT");
  if (port > 65535) throw new Error("TS_PHONE_PORT must be at most 65535");
  const stateDir = absolutePath(env.TS_PHONE_STATE_DIR || resolve(cwd, ".runtime"), "TS_PHONE_STATE_DIR");
  const runtimeDir = env.XDG_RUNTIME_DIR && isAbsolute(env.XDG_RUNTIME_DIR)
    ? resolve(env.XDG_RUNTIME_DIR, "ts-phone")
    : resolve(stateDir, "runtime");
  const bridgeSecretPath = absolutePath(
    env.TS_PHONE_BRIDGE_SECRET_FILE || resolve(stateDir, "bridge.secret"),
    "TS_PHONE_BRIDGE_SECRET_FILE",
  );
  if (bridgeSecretPath === resolve(join(stateDir, "auth.token"))) {
    throw new Error("TS_PHONE_BRIDGE_SECRET_FILE must differ from the public Bearer token file");
  }

  return {
    host: loopbackHost(env.TS_PHONE_HOST),
    port,
    workspaceRoot: absolutePath(
      env.TS_PHONE_WORKSPACES || resolve(cwd, "workspaces"),
      "TS_PHONE_WORKSPACES",
    ),
    stateDir,
    tspiPath: env.TS_PHONE_TSPI
      ? absolutePath(env.TS_PHONE_TSPI, "TS_PHONE_TSPI")
      : undefined,
    bridgeSocketPath: absolutePath(
      env.TS_PHONE_BRIDGE_SOCKET || resolve(runtimeDir, "bridge.sock"),
      "TS_PHONE_BRIDGE_SOCKET",
    ),
    bridgeSecretPath,
    commandTimeoutMs: positiveInteger(
      env.TS_PHONE_COMMAND_TIMEOUT_MS,
      30_000,
      "TS_PHONE_COMMAND_TIMEOUT_MS",
    ),
    shutdownTimeoutMs: positiveInteger(
      env.TS_PHONE_SHUTDOWN_TIMEOUT_MS,
      10_000,
      "TS_PHONE_SHUTDOWN_TIMEOUT_MS",
    ),
    bridgeHeartbeatTimeoutMs: positiveInteger(
      env.TS_PHONE_BRIDGE_HEARTBEAT_TIMEOUT_MS,
      45_000,
      "TS_PHONE_BRIDGE_HEARTBEAT_TIMEOUT_MS",
    ),
    bridgeMaxRecordBytes: positiveInteger(
      env.TS_PHONE_BRIDGE_MAX_RECORD_BYTES,
      8 * 1024 * 1024,
      "TS_PHONE_BRIDGE_MAX_RECORD_BYTES",
    ),
    maxBodyBytes: positiveInteger(env.TS_PHONE_MAX_BODY_BYTES, 128 * 1024, "TS_PHONE_MAX_BODY_BYTES"),
    eventJournalSize: positiveInteger(
      env.TS_PHONE_EVENT_JOURNAL_SIZE,
      1_000,
      "TS_PHONE_EVENT_JOURNAL_SIZE",
    ),
    eventJournalMaxBytes: positiveInteger(
      env.TS_PHONE_EVENT_JOURNAL_MAX_BYTES,
      32 * 1024 * 1024,
      "TS_PHONE_EVENT_JOURNAL_MAX_BYTES",
    ),
  };
}
