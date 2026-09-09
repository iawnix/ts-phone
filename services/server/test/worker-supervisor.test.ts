import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { WorkerSupervisor } from "../src/runtime/worker-supervisor.js";
import { HttpError } from "../src/errors.js";
import { writeFakeTspi } from "./fake-tspi.js";

test("worker supervisor preserves the installation symlink for Workers and lifecycle checks", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-worker-"));
  const executable = join(root, "TSPi");
  const release = join(root, "release");
  await mkdir(release);
  const target = join(release, "TSPi");
  const capture = join(root, "capture.json");
  await writeFile(target, `#!/usr/bin/env node
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
const capture = ${JSON.stringify(capture)};
const args = process.argv.slice(2);
if (args.includes("--session-host-capabilities")) {
  process.stdout.write(JSON.stringify({session_guard_contract: "tspi-session-guard/1"}));
  process.exit(0);
}
if (args.includes("--lifecycle-preflight")) {
  process.stdout.write(JSON.stringify({
    schema_version: "ts-phone-project-preflight/2",
    workspace_root: join(dirname(process.argv[1]), "ts_007"),
    root_agent_active: true,
    session_writers_active: false,
    session_guard_contract: "tspi-session-guard/1",
    remote_calculations: 2,
    unresolved_remote_effects: 1,
  }));
  process.exit(0);
}
writeFileSync(capture, JSON.stringify({
  launcher: process.argv[1],
  args,
  socket: process.env.TS_PHONE_BRIDGE_SOCKET,
  secret: process.env.TS_PHONE_BRIDGE_SECRET_FILE,
}));
process.on("SIGTERM", () => process.exit(0));
setInterval(() => {}, 1000);
`);
  await chmod(target, 0o700);
  await symlink(target, executable);
  const supervisor = new WorkerSupervisor(
    executable,
    1_000,
    join(root, "bridge.sock"),
    join(root, "bridge.secret"),
  );
  try {
    await supervisor.start({
      workspaceId: "ts_007",
      sessionId: "session_4",
      accessMode: "observer",
      name: "Follow-up",
      model: "cpa/gpt-5.6-sol",
    });
    assert.equal(supervisor.owns("ts_007", "session_4"), true);
    const record = await waitForJson(capture);
    assert.equal(record.launcher, executable);
    assert.deepEqual(record.args, [
      "--workspace", "ts_007",
      "--phone-worker",
      "--session-id", "session_4",
      "--phone-access", "observer",
      "--name", "Follow-up",
      "--model", "cpa/gpt-5.6-sol",
    ]);
    assert.equal(record.socket, join(root, "bridge.sock"));
    assert.equal(record.secret, join(root, "bridge.secret"));
    await assert.rejects(
      () => supervisor.verifyWriter("ts_007", join(root, "ts_007"), "session_4", "observer", process.pid),
      (error: unknown) => error instanceof HttpError && error.code === "session_writer_unverified",
    );
    await supervisor.stop("ts_007", "session_4");
    assert.equal(supervisor.owns("ts_007", "session_4"), false);

    assert.deepEqual(await supervisor.inspect("ts_007", join(root, "ts_007")), {
      rootAgentActive: true,
      sessionWritersActive: false,
      remoteCalculations: 2,
      unresolvedRemoteEffects: 1,
    });
  } finally {
    await supervisor.close();
  }
});

test("worker supervisor forgets a process that fails during spawn", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-worker-spawn-error-"));
  const executable = join(root, "TSPi");
  await writeFile(executable, "#!/definitely/missing/interpreter\n");
  await chmod(executable, 0o700);
  const supervisor = new WorkerSupervisor(
    executable,
    1_000,
    join(root, "bridge.sock"),
    join(root, "bridge.secret"),
  );
  const request = {
    workspaceId: "ts_001",
    sessionId: "session_1",
    accessMode: "controller" as const,
  };
  try {
    await assert.rejects(() => supervisor.start(request));
    assert.equal(supervisor.owns("ts_001", "session_1"), false);
    await assert.rejects(() => supervisor.start(request));
    assert.equal(supervisor.owns("ts_001", "session_1"), false);
  } finally {
    await supervisor.close();
  }
});

test("lifecycle guards retain the process for the callback and reject a different workspace root", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-lifecycle-guard-"));
  const executable = join(root, "TSPi");
  await writeFakeTspi(executable, root);
  const supervisor = new WorkerSupervisor(executable, 1000, join(root, "socket"), join(root, "secret"));
  let calls = 0;
  const result = await supervisor.withLifecycleGuard("ts_001", join(root, "ts_001"), async (guard) => {
    guard.assertHeld();
    await new Promise((resolve) => setTimeout(resolve, 25));
    guard.assertHeld();
    calls++;
    return 42;
  });
  assert.equal(result, 42);
  await assert.rejects(
    () => supervisor.withLifecycleGuard("ts_001", join(root, "wrong"), async () => { calls++; }),
    (error: unknown) => error instanceof HttpError && error.code === "workspace_preflight_unavailable",
  );
  assert.equal(calls, 1);
  await assert.rejects(
    () => supervisor.withLifecycleGuard("ts_001", join(root, "ts_001"), async () => { throw new Error("callback failed"); }),
    /callback failed/,
  );
});

async function waitForJson(path: string): Promise<Record<string, any>> {
  const deadline = Date.now() + 2_000;
  while (true) {
    try {
      return JSON.parse(await readFile(path, "utf8")) as Record<string, any>;
    } catch (error) {
      if (Date.now() >= deadline) throw error;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
  }
}

test("concurrent starts after capability probing share exactly one owned process", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-concurrent-worker-"));
  const executable = join(root, "TSPi");
  await writeFakeTspi(executable, root);
  const supervisor = new WorkerSupervisor(executable, 1000, join(root, "socket"), join(root, "secret"));
  const request = { workspaceId: "ts_001", sessionId: "session_1", accessMode: "controller" as const, launchId: "one-launch" };
  try {
    const first = supervisor.start(request);
    await assert.rejects(() => supervisor.start({ ...request, launchId: "different-launch" }),
      (error: unknown) => error instanceof HttpError && error.code === "worker_identity_conflict");
    const [left, right] = await Promise.all([first, supervisor.start(request)]);
    assert.equal(left.exit, right.exit);
    assert.deepEqual(supervisor.request(request.workspaceId, request.sessionId), request);
    await assert.rejects(() => supervisor.start({ ...request, launchId: "different-launch" }),
      (error: unknown) => error instanceof HttpError && error.code === "worker_identity_conflict");
  } finally { await supervisor.close(); }
});
