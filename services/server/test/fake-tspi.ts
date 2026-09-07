import { chmod, writeFile } from "node:fs/promises";

// Exercises the private process transport without a scientific runtime.
export async function writeFakeTspi(path: string, workspaceRoot: string, rootAgentActive = false): Promise<void> {
  await writeFile(path, `#!/usr/bin/env node
import { join } from "node:path";
import { createInterface } from "node:readline";
const args = process.argv.slice(2);
const guarded = args.includes("--lifecycle-guard");
if (guarded || args.includes("--lifecycle-preflight")) {
  process.stdout.write(JSON.stringify({
    schema_version: guarded ? "ts-phone-project-guard/1" : "ts-phone-project-preflight/2",
    workspace_root: join(${JSON.stringify(workspaceRoot)}, args[args.indexOf("--workspace") + 1]),
    root_agent_active: ${rootAgentActive},
    remote_calculations: 0,
    unresolved_remote_effects: 0,
    ...(guarded ? {guard_acquired: ${!rootAgentActive}} : {}),
  }) + "\\n");
  if (guarded) { process.stdin.resume(); process.stdin.on("end", () => process.exit(0)); }
} else {
  createInterface({input: process.stdin}).on("line", line => {
    const command = JSON.parse(line);
    if (command.type !== "prompt") return;
    const success = command.message !== "reject-before-model";
    setTimeout(() => process.stdout.write(JSON.stringify({
      type: "response", id: command.id, command: "prompt", success,
      ...(success ? {} : {error: "No API key: private-test-key"}),
    }) + "\\n"), 20);
  });
  process.on("SIGTERM", () => process.exit(0));
  setInterval(() => {}, 1000);
}
`);
  await chmod(path, 0o700);
}
