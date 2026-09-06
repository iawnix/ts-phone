import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ServerConfig } from "../src/config.js";
import { createTsPhoneHttpServer } from "../src/http-server.js";
import { readBearerToken } from "../src/security.js";
import { writeFakeTspi } from "./fake-tspi.js";

test("project and session management is durable, revisioned, and lifecycle-filtered", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-management-http-"));
  const workspaceRoot = join(root, "workspaces");
  await mkdir(join(workspaceRoot, "ts_001"), { recursive: true });
  const config = fixtureConfig(root, workspaceRoot);
  await writeFakeTspi(config.tspiPath!, workspaceRoot);
  let application = await createTsPhoneHttpServer(config);
  let address = await application.listen();
  const token = await readBearerToken(config.stateDir);
  let baseUrl = `http://127.0.0.1:${address.port}`;
  const request = (path: string, init: RequestInit = {}) => fetch(`${baseUrl}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, ...init.headers },
  });
  const json = (method: string, body: unknown): RequestInit => ({
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  try {
    const unmanagedResponse = await request("/api/v4/workspaces");
    assert.equal(unmanagedResponse.status, 200);
    const unmanaged = await data<Array<Record<string, unknown>>>(unmanagedResponse);
    assert.equal(unmanaged[0]?.id, "ts_001");
    assert.equal(unmanaged[0]?.managed, false);
    assert.equal(unmanaged[0]?.managementRevision, "unmanaged");

    const renamedResponse = await request(
      "/api/v4/workspaces/ts_001",
      json("PATCH", { name: "Legacy project", managementRevision: "unmanaged" }),
    );
    assert.equal(renamedResponse.status, 200);
    const renamed = await data<Record<string, unknown>>(renamedResponse);
    assert.equal(renamed.name, "Legacy project");
    assert.equal(renamed.managed, true);
    assert.match(String(renamed.managementRevision), /^[0-9a-f-]{36}$/);

    const staleRename = await request(
      "/api/v4/workspaces/ts_001",
      json("PATCH", { name: "Stale", managementRevision: "unmanaged" }),
    );
    assert.equal(staleRename.status, 409);

    const createResponse = await request(
      "/api/v4/workspaces",
      json("POST", { name: "Catalytic cycle" }),
    );
    assert.equal(createResponse.status, 201);
    const created = await data<{
      workspace: Record<string, unknown>;
      session: Record<string, unknown>;
    }>(createResponse);
    assert.equal(created.workspace.id, "ts_002");
    assert.equal(created.session.sessionId, "session_1");
    assert.equal(created.session.canActivate, true);

    const createSessionResponse = await request(
      "/api/v4/workspaces/ts_002/sessions",
      json("POST", { name: "Alternative path", accessMode: "observer", model: "cpa/gpt-5.6-sol" }),
    );
    assert.equal(createSessionResponse.status, 201);
    let session = await data<Record<string, unknown>>(createSessionResponse);
    assert.equal(session.sessionId, "session_2");
    assert.equal(session.accessMode, "observer");

    const archiveSessionResponse = await request(
      "/api/v4/workspaces/ts_002/sessions/session_2/archive",
      json("POST", { managementRevision: session.managementRevision }),
    );
    assert.equal(archiveSessionResponse.status, 200);
    session = await data<Record<string, unknown>>(archiveSessionResponse);
    assert.equal(session.lifecycleState, "archived");
    const activeSessions = await data<Array<Record<string, unknown>>>(
      await request("/api/v4/workspaces/ts_002/sessions"),
    );
    assert.deepEqual(activeSessions.map((value) => value.sessionId), ["session_1"]);
    const archivedSessions = await data<Array<Record<string, unknown>>>(
      await request("/api/v4/workspaces/ts_002/sessions?state=archived"),
    );
    assert.equal(archivedSessions[0]?.sessionId, "session_2");

    const restoreSessionResponse = await request(
      "/api/v4/workspaces/ts_002/sessions/session_2/restore",
      json("POST", { managementRevision: session.managementRevision }),
    );
    session = await data<Record<string, unknown>>(restoreSessionResponse);
    const trashSessionResponse = await request(
      "/api/v4/workspaces/ts_002/sessions/session_2/trash",
      json("POST", { managementRevision: session.managementRevision }),
    );
    session = await data<Record<string, unknown>>(trashSessionResponse);
    assert.equal(session.lifecycleState, "trashed");
    assert.equal(typeof session.deletedAt, "string");
    assert.equal(session.purgeAfter, undefined);
    const purgeSessionResponse = await request(
      "/api/v4/workspaces/ts_002/sessions/session_2/purge",
      json("POST", { managementRevision: session.managementRevision, confirmation: "session_2" }),
    );
    assert.equal(purgeSessionResponse.status, 200);

    const preflightResponse = await request("/api/v4/workspaces/ts_002/deletion-preflight");
    assert.equal(preflightResponse.status, 200);
    const preflight = await data<Record<string, unknown>>(preflightResponse);
    assert.equal(preflight.canDelete, true);
    assert.deepEqual(
      [preflight.activeWorkers, preflight.remoteCalculations, preflight.pendingApprovals, preflight.unresolvedRemoteEffects],
      [0, 0, 0, 0],
    );

    let project = await data<Record<string, unknown>>(
      await request("/api/v4/workspaces/ts_002"),
    );
    const trashWorkspaceResponse = await request(
      "/api/v4/workspaces/ts_002/trash",
      json("POST", { managementRevision: project.managementRevision }),
    );
    project = await data<Record<string, unknown>>(trashWorkspaceResponse);
    assert.equal(project.lifecycleState, "trashed");
    assert.equal((await data<unknown[]>(await request("/api/v4/workspaces"))).length, 1);
    assert.equal((await data<unknown[]>(await request("/api/v4/workspaces?state=trashed"))).length, 1);

    await application.close();
    application = await createTsPhoneHttpServer(config);
    address = await application.listen();
    baseUrl = `http://127.0.0.1:${address.port}`;
    const afterRestart = await data<Array<Record<string, unknown>>>(
      await request("/api/v4/workspaces?state=trashed"),
    );
    assert.equal(afterRestart[0]?.id, "ts_002");
    assert.equal(afterRestart[0]?.name, "Catalytic cycle");

    const purgeWorkspaceResponse = await request(
      "/api/v4/workspaces/ts_002/purge",
      json("POST", { managementRevision: project.managementRevision, confirmation: "ts_002" }),
    );
    assert.equal(purgeWorkspaceResponse.status, 200);
    await assert.rejects(() => access(join(workspaceRoot, "ts_002")));
    assert.equal((await data<unknown[]>(await request("/api/v4/workspaces?state=trashed"))).length, 0);

    assert.equal((await stat(join(config.stateDir, "management.json"))).mode & 0o777, 0o600);
  } finally {
    await application.close();
  }
});

test("management API rejects malformed lifecycle and purge requests", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-management-validation-"));
  const workspaceRoot = join(root, "workspaces");
  await mkdir(join(workspaceRoot, "ts_001"), { recursive: true });
  const config = fixtureConfig(root, workspaceRoot);
  const application = await createTsPhoneHttpServer(config);
  const address = await application.listen();
  const token = await readBearerToken(config.stateDir);
  const request = (path: string, body?: unknown) => fetch(`http://127.0.0.1:${address.port}${path}`, {
    ...(body === undefined ? {} : {
      method: "POST",
      body: JSON.stringify(body),
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    }),
    ...(body === undefined ? { headers: { Authorization: `Bearer ${token}` } } : {}),
  });
  try {
    assert.equal((await request("/api/v4/workspaces?state=deleted")).status, 400);
    assert.equal((await request("/api/v4/workspaces?state=active&state=archived")).status, 400);
    assert.equal((await request("/api/v4/workspaces", { name: " bad " })).status, 400);
    assert.equal((await request("/api/v4/workspaces/ts_001/trash", {
      managementRevision: "not-a-revision",
    })).status, 400);
    assert.equal((await request("/api/v4/workspaces/ts_001/purge", {
      managementRevision: "unmanaged",
      confirmation: "another-project",
    })).status, 400);
  } finally {
    await application.close();
  }
});

function fixtureConfig(root: string, workspaceRoot: string): ServerConfig {
  return {
    host: "127.0.0.1",
    port: 0,
    workspaceRoot,
    stateDir: join(root, "state"),
    tspiPath: join(root, "TSPi"),
    bridgeSocketPath: join(root, "run", "bridge.sock"),
    bridgeSecretPath: join(root, "state", "bridge.secret"),
    commandTimeoutMs: 2_000,
    shutdownTimeoutMs: 2_000,
    bridgeHeartbeatTimeoutMs: 10_000,
    bridgeMaxRecordBytes: 1024 * 1024,
    maxBodyBytes: 128 * 1024,
    eventJournalSize: 100,
    eventJournalMaxBytes: 1024 * 1024,
  };
}

async function data<T>(response: Response): Promise<T> {
  const value = await response.json() as { data: T };
  return value.data;
}
