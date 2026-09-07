import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ServerConfig } from "../src/config.js";
import { HttpError } from "../src/errors.js";
import { ManagementStore } from "../src/management-store.js";
import { WorkspaceHub } from "../src/runtime/workspace-hub.js";
import { WorkerSupervisor } from "../src/runtime/worker-supervisor.js";
import { writeFakeTspi } from "./fake-tspi.js";
import {
  WorkspaceRegistry,
  type QuarantinedPath,
} from "../src/workspace-registry.js";

test("stale lifecycle requests preserve workers and unready runtimes block deletion", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-workspace-lifecycle-"));
  const workspaceRoot = join(root, "workspaces");
  const stateDir = join(root, "state");
  await mkdir(workspaceRoot, { recursive: true });
  const executable = join(root, "TSPi");
  await writeFakeTspi(executable, workspaceRoot);

  const config = fixtureConfig(root, workspaceRoot, stateDir, executable);
  const management = await ManagementStore.open(stateDir);
  const workers = new WorkerSupervisor(
    executable,
    config.shutdownTimeoutMs,
    config.bridgeSocketPath,
    config.bridgeSecretPath,
  );
  const hub = new WorkspaceHub(config, "bridge-secret", management, workers);
  try {
    const created = await hub.createWorkspace({ name: "Catalytic cycle" });
    const staleRevision = created.workspace.managementRevision;
    await workers.start({
      workspaceId: created.workspace.id,
      sessionId: created.session.sessionId,
      accessMode: "controller",
    });
    assert.equal(workers.owns("ts_001", "session_1"), true);

    const renamed = await hub.renameWorkspace("ts_001", {
      name: "Renamed cycle",
      managementRevision: staleRevision,
    });
    await assert.rejects(
      () => hub.archiveWorkspace("ts_001", { managementRevision: staleRevision }),
      (error: unknown) => (
        error instanceof HttpError
        && error.code === "workspace_management_changed"
      ),
    );
    assert.equal(workers.owns("ts_001", "session_1"), true);

    const preflight = await hub.workspaceDeletionPreflight("ts_001");
    assert.equal(preflight.activeWorkers, 1);
    assert.equal(preflight.canDelete, false);
    await assert.rejects(() => hub.trashWorkspace("ts_001", {
      managementRevision: renamed.managementRevision,
    }), (error: unknown) => error instanceof HttpError && error.code === "workspace_delete_blocked");
    assert.equal(workers.owns("ts_001", "session_1"), true);
  } finally {
    await hub.close();
  }
});

test("an unbridged Root Agent blocks project trash and permanent deletion", async () => {
  const fixture = await createLifecycleFixture("external-root");
  const hub = new WorkspaceHub(fixture.config, "bridge-secret", fixture.management, fixture.workers);
  try {
    const created = await hub.createWorkspace({ name: "Manual Root" });
    await writeFakeTspi(fixture.config.tspiPath!, fixture.workspaceRoot, true);
    const preflight = await hub.workspaceDeletionPreflight(created.workspace.id);
    assert.equal(preflight.activeWorkers, 1);
    assert.equal(preflight.canDelete, false);
    await assert.rejects(
      () => hub.trashWorkspace(created.workspace.id, { managementRevision: created.workspace.managementRevision }),
      (error: unknown) => error instanceof HttpError && error.code === "workspace_delete_blocked",
    );
    assert.equal(fixture.management.workspace(created.workspace.id)?.lifecycleState, "active");
    await writeFakeTspi(fixture.config.tspiPath!, fixture.workspaceRoot);
    const trashed = await hub.trashWorkspace(created.workspace.id, { managementRevision: created.workspace.managementRevision });
    await writeFakeTspi(fixture.config.tspiPath!, fixture.workspaceRoot, true);
    await assert.rejects(
      () => hub.purgeWorkspace(created.workspace.id, {
        managementRevision: trashed.managementRevision, confirmation: created.workspace.id,
      }),
      (error: unknown) => error instanceof HttpError && error.code === "workspace_delete_blocked",
    );
    await access(join(fixture.workspaceRoot, created.workspace.id));
    assert.equal(fixture.management.workspace(created.workspace.id)?.managementRevision, trashed.managementRevision);
  } finally {
    await hub.close();
  }
});

test("failed project purge restores both workspace data and management metadata", async () => {
  const fixture = await createLifecycleFixture("project-purge-recovery");
  const registry = new DeleteFailingRegistry(fixture.workspaceRoot);
  const hub = new WorkspaceHub(
    fixture.config,
    "bridge-secret",
    fixture.management,
    fixture.workers,
    registry,
  );
  try {
    const created = await hub.createWorkspace({ name: "Recoverable project" });
    const trashed = await hub.trashWorkspace(created.workspace.id, {
      managementRevision: created.workspace.managementRevision,
    });

    await assert.rejects(
      () => hub.purgeWorkspace(created.workspace.id, {
        managementRevision: trashed.managementRevision,
        confirmation: created.workspace.id,
      }),
      /injected quarantine deletion failure/,
    );

    await access(join(fixture.workspaceRoot, created.workspace.id));
    const recovered = fixture.management.workspace(created.workspace.id);
    assert.equal(recovered?.lifecycleState, "trashed");
    assert.equal(recovered?.managementRevision, trashed.managementRevision);
    assert.deepEqual(
      (await hub.listWorkspaces("trashed")).map((workspace) => workspace.id),
      [created.workspace.id],
    );

    await hub.purgeWorkspace(created.workspace.id, {
      managementRevision: trashed.managementRevision,
      confirmation: created.workspace.id,
    });
    await assert.rejects(() => access(join(fixture.workspaceRoot, created.workspace.id)));
    assert.equal(fixture.management.workspace(created.workspace.id), undefined);
  } finally {
    await hub.close();
  }
});

test("failed conversation purge restores both Pi history and management metadata", async () => {
  const fixture = await createLifecycleFixture("session-purge-recovery");
  const registry = new DeleteFailingRegistry(fixture.workspaceRoot);
  const hub = new WorkspaceHub(
    fixture.config,
    "bridge-secret",
    fixture.management,
    fixture.workers,
    registry,
  );
  try {
    const created = await hub.createWorkspace({ name: "Recoverable session" });
    const sessionsRoot = join(
      fixture.workspaceRoot,
      created.workspace.id,
      ".pi",
      "sessions",
    );
    const sessionPath = join(sessionsRoot, "session_1.jsonl");
    await mkdir(sessionsRoot, { recursive: true });
    await writeFile(sessionPath, `${JSON.stringify({
      type: "session",
      version: 3,
      id: created.session.sessionId,
      timestamp: new Date().toISOString(),
      cwd: join(fixture.workspaceRoot, created.workspace.id),
    })}\n`);
    await hub.listSessions(created.workspace.id);
    const trashed = await hub.trashSession(
      created.workspace.id,
      created.session.sessionId,
      { managementRevision: created.session.managementRevision },
    );

    await assert.rejects(
      () => hub.purgeSession(created.workspace.id, created.session.sessionId, {
        managementRevision: trashed.managementRevision,
        confirmation: created.session.sessionId,
      }),
      /injected quarantine deletion failure/,
    );

    await access(sessionPath);
    const recovered = fixture.management.session(
      created.workspace.id,
      created.session.sessionId,
    );
    assert.equal(recovered?.lifecycleState, "trashed");
    assert.equal(recovered?.managementRevision, trashed.managementRevision);
    assert.deepEqual(
      (await hub.listSessions(created.workspace.id, "trashed"))
        .map((session) => session.sessionId),
      [created.session.sessionId],
    );

    await hub.purgeSession(created.workspace.id, created.session.sessionId, {
      managementRevision: trashed.managementRevision,
      confirmation: created.session.sessionId,
    });
    await assert.rejects(() => access(sessionPath));
    assert.equal(
      fixture.management.session(created.workspace.id, created.session.sessionId),
      undefined,
    );
  } finally {
    await hub.close();
  }
});

class DeleteFailingRegistry extends WorkspaceRegistry {
  #shouldFail = true;

  override async deleteQuarantine(value: QuarantinedPath): Promise<void> {
    if (this.#shouldFail) {
      this.#shouldFail = false;
      throw new Error("injected quarantine deletion failure");
    }
    await super.deleteQuarantine(value);
  }
}

async function createLifecycleFixture(label: string): Promise<{
  workspaceRoot: string;
  config: ServerConfig;
  management: ManagementStore;
  workers: WorkerSupervisor;
}> {
  const root = await mkdtemp(join(tmpdir(), `ts-phone-${label}-`));
  const workspaceRoot = join(root, "workspaces");
  const stateDir = join(root, "state");
  await mkdir(workspaceRoot, { recursive: true });
  const executable = join(root, "TSPi");
  await writeFakeTspi(executable, workspaceRoot);
  const config = fixtureConfig(root, workspaceRoot, stateDir, executable);
  const management = await ManagementStore.open(stateDir);
  const workers = new WorkerSupervisor(
    executable,
    config.shutdownTimeoutMs,
    config.bridgeSocketPath,
    config.bridgeSecretPath,
  );
  return { workspaceRoot, config, management, workers };
}

function fixtureConfig(
  root: string,
  workspaceRoot: string,
  stateDir: string,
  tspiPath: string,
): ServerConfig {
  return {
    host: "127.0.0.1",
    port: 0,
    workspaceRoot,
    stateDir,
    tspiPath,
    bridgeSocketPath: join(root, "run", "bridge.sock"),
    bridgeSecretPath: join(stateDir, "bridge.secret"),
    commandTimeoutMs: 2_000,
    shutdownTimeoutMs: 1_000,
    bridgeHeartbeatTimeoutMs: 10_000,
    bridgeMaxRecordBytes: 1024 * 1024,
    maxBodyBytes: 128 * 1024,
    eventJournalSize: 100,
    eventJournalMaxBytes: 1024 * 1024,
  };
}
