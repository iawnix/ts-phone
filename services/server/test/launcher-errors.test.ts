import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { HttpError } from "../src/errors.js";
import { readLauncherError } from "../src/runtime/launcher-errors.js";
import { runLifecycle } from "../src/runtime/lifecycle-client.js";
import { WorkerSupervisor } from "../src/runtime/worker-supervisor.js";

for (const code of ["session_guard_upgrade_required", "session_guard_invalid", "session_writer_inspection_failed"]) {
  test(`lifecycle retains ${code} without forwarding private diagnostics`, async () => {
    const root = await mkdtemp(join(tmpdir(), "ts-phone-launcher-error-"));
    const command = join(root, "TSPi");
    const diagnostic = "private-environment-value\n" + JSON.stringify({ type: "tspi.startup_error", code }) + "\n";
    await writeFile(command, `#!/usr/bin/env node\nprocess.stderr.write(${JSON.stringify(diagnostic)},()=>process.exit(1));\n`, { mode: 0o700 });
    await assert.rejects(() => runLifecycle(command, "ts_001", root), (error: unknown) => {
      assert.ok(error instanceof HttpError);
      assert.equal(error.code, code);
      assert.ok(!error.message.includes("private-environment-value"));
      return true;
    });
    const supervisor = new WorkerSupervisor(command, 1_000, join(root, "bridge.sock"), join(root, "bridge.secret"));
    for (const check of [
      () => supervisor.checkCompatibility(),
      () => supervisor.verifyWriter("ts_001", root, "session_1", "controller", process.pid),
    ]) {
      await assert.rejects(check, (error: unknown) => {
        assert.ok(error instanceof HttpError);
        assert.equal(error.code, code);
        assert.ok(!error.message.includes("private-environment-value"));
        return true;
      });
    }
  });
}

test("unknown and extended launcher error records never expose their payload", () => {
  assert.equal(readLauncherError(undefined), undefined);
  assert.equal(readLauncherError("private diagnostic"), undefined);
  assert.equal(readLauncherError(JSON.stringify({ type: "tspi.startup_error", code: "unknown" })), undefined);
  assert.equal(readLauncherError(JSON.stringify({ type: "tspi.startup_error", code: "session_guard_invalid", secret: "private" })), undefined);
});
