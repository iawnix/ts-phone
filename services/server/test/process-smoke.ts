import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, mkdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import type { ServerConfig } from "../src/config.js";
import { connectFakeBridge, type FakeBridge } from "./helpers.js";

const serverRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = await mkdtemp(join(tmpdir(), "ts-phone-process-smoke-"));
const workspaceRoot = join(root, "workspaces");
const stateDir = join(root, "state");
const bridgeSocketPath = join(root, "run", "bridge.sock");
const bridgeSecretPath = join(stateDir, "bridge.secret");
const port = parsePort(process.env.TS_PHONE_SMOKE_PORT || "22113");
const baseUrl = `http://127.0.0.1:${port}`;
await mkdir(join(workspaceRoot, "smoke"), { recursive: true });
const config: ServerConfig = {
  host: "127.0.0.1",
  port,
  workspaceRoot,
  stateDir,
  bridgeSocketPath,
  bridgeSecretPath,
  commandTimeoutMs: 2_000,
  bridgeHeartbeatTimeoutMs: 10_000,
  bridgeMaxRecordBytes: 1024 * 1024,
  maxBodyBytes: 128 * 1024,
  eventJournalSize: 100,
  eventJournalMaxBytes: 1024 * 1024,
};

const child = spawn(process.execPath, [join(serverRoot, "dist", "index.js")], {
  cwd: serverRoot,
  env: {
    ...process.env,
    TS_PHONE_HOST: "127.0.0.1",
    TS_PHONE_PORT: String(port),
    TS_PHONE_WORKSPACES: workspaceRoot,
    TS_PHONE_STATE_DIR: stateDir,
    TS_PHONE_BRIDGE_SOCKET: bridgeSocketPath,
    TS_PHONE_BRIDGE_SECRET_FILE: bridgeSecretPath,
    TS_PHONE_COMMAND_TIMEOUT_MS: "2000",
  },
  stdio: ["ignore", "pipe", "pipe"],
});
let stdout = "";
let stderr = "";
let bridge: FakeBridge | undefined;
child.stdout.on("data", (chunk: Buffer) => { stdout += chunk.toString(); });
child.stderr.on("data", (chunk: Buffer) => { stderr += chunk.toString(); });

try {
  await waitForHealth();
  assert.match(stdout, new RegExp(`TS Phone listening on http://127\\.0\\.0\\.1:${port}`));

  const token = (await readFile(join(stateDir, "auth.token"), "utf8")).trim();
  const authorization = { Authorization: `Bearer ${token}` };
  assert.equal((await fetch(`${baseUrl}/api/v3/workspaces`)).status, 401);

  const workspaces = await fetch(`${baseUrl}/api/v3/workspaces`, { headers: authorization });
  assert.equal(workspaces.status, 200);
  assert.match(await workspaces.text(), /"smoke"/);

  bridge = await connectFakeBridge(config, "smoke", join(workspaceRoot, "smoke"));
  await waitForWorkspaceState(authorization, "idle");
  const sessionRevision = await readSessionRevision(authorization);

  const eventResponse = await fetch(`${baseUrl}/api/v3/workspaces/smoke/sessions/session-test/events`, {
    headers: authorization,
  });
  assert.equal(eventResponse.status, 200);
  const reader = eventResponse.body?.getReader();
  assert.ok(reader);
  try {
    assert.equal((await fetch(`${baseUrl}/api/v3/workspaces/smoke/sessions/session-test/messages`, {
      method: "POST",
      headers: { ...authorization, "Content-Type": "application/json" },
      body: JSON.stringify({ clientMessageId: "process-smoke-1", sessionRevision, message: "process-smoke" }),
    })).status, 202);
    assert.match(await readSseUntil(reader, "reply:process-smoke"), /event: message_update/);
  } finally {
    await reader.cancel();
  }

  const messages = await fetch(`${baseUrl}/api/v3/workspaces/smoke/sessions/session-test/messages`, {
    headers: authorization,
  });
  assert.equal(messages.status, 200);
  assert.match(await messages.text(), /reply:process-smoke/);

  process.stdout.write(`process smoke passed on 127.0.0.1:${port}\n`);
} finally {
  await bridge?.close();
  if (child.exitCode === null) child.kill("SIGTERM");
  await Promise.race([
    once(child, "exit"),
    new Promise((resolveExit) => setTimeout(resolveExit, 2_000)),
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
  await rm(root, { recursive: true, force: true });
}

async function waitForWorkspaceState(
  authorization: { Authorization: string },
  expected: string,
): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const response = await fetch(`${baseUrl}/api/v3/workspaces`, { headers: authorization });
    const payload = await response.json() as { data?: Array<{ runtimeState?: string }> };
    if (payload.data?.[0]?.runtimeState === expected) return;
    await new Promise((resolveWait) => setTimeout(resolveWait, 20));
  }
  throw new Error(`Workspace state did not become ${expected}`);
}

async function readSessionRevision(authorization: { Authorization: string }): Promise<string> {
  const response = await fetch(`${baseUrl}/api/v3/workspaces/smoke/sessions`, { headers: authorization });
  const payload = await response.json() as { data?: Array<{ sessionRevision?: string }> };
  const revision = payload.data?.[0]?.sessionRevision;
  if (!revision) throw new Error("Smoke session revision was unavailable");
  return revision;
}

async function waitForHealth(): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`TS Phone process exited early (${child.exitCode}): ${stderr.slice(-2_000)}`);
    }
    try {
      const response = await fetch(`${baseUrl}/healthz`);
      if (response.ok) return;
    } catch {
      // The loopback listener may not be ready yet.
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 20));
  }
  throw new Error(`TS Phone health check timed out: ${stderr.slice(-2_000)}`);
}

async function readSseUntil(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  expected: string,
): Promise<string> {
  const decoder = new TextDecoder();
  let buffer = "";
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const records = buffer.split("\n\n");
    buffer = records.pop() || "";
    const match = records.find((record) => record.includes(expected));
    if (match) return match;
  }
  throw new Error(`SSE event was not observed: ${expected}`);
}

function parsePort(value: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > 65_535) {
    throw new Error("TS_PHONE_SMOKE_PORT must be an integer between 1 and 65535");
  }
  return parsed;
}
