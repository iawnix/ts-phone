import { chmod, writeFile } from "node:fs/promises";

// Exercises the private process transport without a scientific runtime.
export async function writeFakeTspi(path: string, workspaceRoot: string, rootAgentActive = false, options: {
  bridge?: boolean;
  snapshotDelayMs?: number;
  promptProblem?: "model_auth_missing" | "model_unavailable";
  guardCompatible?: boolean;
  writerVerified?: boolean;
  exitBeforeBridge?: boolean;
  startupStderr?: string;
  modelControl?: boolean;
  turnDelayMs?: number;
  retryOutcome?: "completed" | "failed" | "cancelled";
} = {}): Promise<void> {
  await writeFile(path, `#!/usr/bin/env node
import { join } from "node:path";
import { createInterface } from "node:readline";
import { createConnection } from "node:net";
import { readFileSync, writeFileSync, appendFileSync } from "node:fs";
const args = process.argv.slice(2);
const guarded = args.includes("--lifecycle-guard");
if (args.includes("--phone-models")) {
  process.stdout.write(JSON.stringify({schemaVersion: "ts-phone-models/1", models: [
    { provider: "test", id: "fake-model", name: "Fake model", contextWindow: 128000 },
    { provider: "test", id: "second", name: "Second model", contextWindow: 128000 }
  ]}) + "\\n");
} else if (args.includes("--session-host-capabilities")) {
  process.stdout.write(JSON.stringify({session_guard_contract: ${JSON.stringify(options.guardCompatible === false ? "unsupported" : "tspi-session-guard/1")}}) + "\\n");
} else if (args.includes("--session-writer-check")) {
  process.stdout.write(JSON.stringify({session_guard_contract: "tspi-session-guard/1", verified: ${options.writerVerified !== false},
    workspace_root: join(${JSON.stringify(workspaceRoot)}, args[args.indexOf("--workspace") + 1]),
    session_id: args[args.indexOf("--session-id") + 1], access_mode: args[args.indexOf("--phone-access") + 1],
    pid: Number(args[args.indexOf("--writer-pid") + 1]),
  }) + "\\n");
} else if (guarded || args.includes("--lifecycle-preflight")) {
  process.stdout.write(JSON.stringify({
    schema_version: guarded ? "ts-phone-project-guard/1" : "ts-phone-project-preflight/2",
    workspace_root: join(${JSON.stringify(workspaceRoot)}, args[args.indexOf("--workspace") + 1]),
    root_agent_active: ${rootAgentActive},
    session_writers_active: false,
    session_guard_contract: "tspi-session-guard/1",
    remote_calculations: 0,
    unresolved_remote_effects: 0,
    ...(guarded ? {guard_acquired: ${!rootAgentActive}} : {}),
  }) + "\\n");
  if (guarded) { process.stdin.resume(); process.stdin.on("end", () => process.exit(0)); }
} else {
  let publish;
  let currentModel = "fake-model";
  let sequence = 1;
  let runIndex = 0;
  if (${options.exitBeforeBridge === true}) {
    await new Promise(resolve => process.stderr.write(${JSON.stringify(options.startupStderr ?? "private-provider-diagnostic\n")}, resolve));
    process.exit(1);
  }
  writeFileSync(${JSON.stringify(`${path}.launch`)}, JSON.stringify({launchId: process.env.TS_PHONE_LAUNCH_ID, pid: process.pid}));
  if (${options.bridge === true}) {
    const workspaceId = args[args.indexOf("--workspace") + 1];
    const sessionId = args[args.indexOf("--session-id") + 1];
    const mode = args[args.indexOf("--phone-access") + 1];
    const socket = createConnection(process.env.TS_PHONE_BRIDGE_SOCKET);
    const identity = { protocolVersion: "ts-phone-bridge/3", workspaceId, sessionId,
      instanceEpoch: "fake-" + process.pid, sessionGeneration: 1 };
    const write = record => socket.write(JSON.stringify(record) + "\\n");
    publish = (eventType, payload) => write({...identity, type: "event.publish", sequence: ++sequence, eventType, payload});
    socket.on("connect", () => {
      appendFileSync(${JSON.stringify(`${path}.starts`)}, JSON.stringify({sessionId, mode}) + "\\n");
      write({ ...identity, type: "bridge.register", workspaceRoot: join(${JSON.stringify(workspaceRoot)}, workspaceId),
        accessMode: mode, launchId: process.env.TS_PHONE_LAUNCH_ID || undefined,
        secret: readFileSync(process.env.TS_PHONE_BRIDGE_SECRET_FILE, "utf8").trim(), pid: process.pid });
    });
    socket.once("data", () => setTimeout(() => write({ ...identity, type: "session.snapshot", sequence: 1,
      snapshot: {sessionId, model: "test/fake-model", modelControl: ${options.modelControl === true}, isStreaming: false, messages: [],
        ${options.promptProblem ? `promptProblem: ${JSON.stringify(options.promptProblem)},` : ""}
      } }), ${options.snapshotDelayMs ?? 0}));
    socket.on("error", () => {});
  }
  createInterface({input: process.stdin}).on("line", line => {
    const command = JSON.parse(line);
    if (command.type === "set_model") {
      const success = command.modelId !== "rejected";
      if (success) currentModel = command.modelId;
      setTimeout(() => process.stdout.write(JSON.stringify({type: "response", id: command.id,
        command: "set_model", success, ...(success ? {data: {provider: command.provider, id: command.modelId,
          name: command.modelId, contextWindow: 128000}} : {error: "Model not found: private-config"})}) + "\\n"), 80);
      return;
    }
    if (command.type !== "prompt") return;
    const success = command.message !== "reject-before-model";
    if (success && ${options.turnDelayMs !== undefined} && publish) {
      const agentRunId = "run-" + process.pid + "-" + (++runIndex);
      appendFileSync(${JSON.stringify(`${path}.prompts`)}, JSON.stringify({sessionId: args[args.indexOf("--session-id") + 1],
        message: command.message, model: currentModel, at: Date.now(), followUp: command.streamingBehavior}) + "\\n");
      publish("input", {type: "input", source: "rpc", text: command.message});
      publish("agent_start", {type: "agent_start", agentRunId});
      if (${options.retryOutcome !== undefined} && runIndex === 1) {
        publish("message_end", {type: "message_end", message: {role: "assistant", content: [], outputState: "failed"}});
        setTimeout(() => publish("agent_start", {type: "agent_start", agentRunId, attempt: 2}), ${Math.floor((options.turnDelayMs ?? 100) / 2)});
      }
      setTimeout(() => {
        appendFileSync(${JSON.stringify(`${path}.settled`)}, JSON.stringify({agentRunId, at: Date.now()}) + "\\n");
        const status = runIndex === 1 ? ${JSON.stringify(options.retryOutcome ?? "completed")} : "completed";
        publish("agent_settled", {type: "agent_settled", agentRunId, outcome: {status,
          ...(status === "failed" ? {problem: "provider_unavailable", httpStatus: 503} : {})}});
      }, ${options.turnDelayMs ?? 0});
    }
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
