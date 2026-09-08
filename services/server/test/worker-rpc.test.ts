import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import test from "node:test";
import { WorkerRpc, promptFailure } from "../src/runtime/worker-rpc.js";

test("model storage failures take precedence over missing authentication", () => {
  const error = promptFailure("No API key: EROFS auth.json.lock private-key");
  assert.equal(error.code, "model_storage_unavailable");
  assert.doesNotMatch(error.message, /private-key/);
});

test("Worker RPC preserves explicit model readiness codes and redacts details", () => {
  for (const code of ["model_unavailable", "model_auth_missing", "model_storage_unavailable", "model_check_failed"]) {
    const error = promptFailure(`${code}: private-key`);
    assert.equal(error.code, code);
    assert.doesNotMatch(error.message, /private-key/);
  }
});

test("Worker RPC waits for its exact prompt preflight response, not an input event", async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const rpc = new WorkerRpc(input, output, () => assert.fail("unexpected extension failure"));
  try {
    let accepted = false;
    const pending = rpc.prompt("hello", true).then(() => { accepted = true; });
    const command = JSON.parse(input.read().toString());
    assert.equal(command.type, "prompt");
    assert.equal(command.streamingBehavior, "followUp");
    output.write(JSON.stringify({ type: "input", text: "hello" }) + "\n");
    output.write(JSON.stringify({ type: "response", id: "other", command: "prompt", success: true }) + "\n");
    await Promise.resolve();
    assert.equal(accepted, false);
    const reply = JSON.stringify({ type: "response", id: command.id, command: "prompt", success: true });
    output.write(reply.slice(0, 20));
    output.write(reply.slice(20) + "\n");
    await pending;
    assert.equal(accepted, true);
  } finally { rpc.close(); }
});

test("Worker RPC preserves a safe preflight failure and consumes extension errors", async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const errors: string[] = [];
  const rpc = new WorkerRpc(input, output, (error) => errors.push(error.code));
  try {
    const pending = rpc.prompt("hello", false);
    const command = JSON.parse(input.read().toString());
    const rejected = assert.rejects(pending, (error: any) => {
      assert.equal(error.code, "model_auth_missing");
      assert.doesNotMatch(error.message, /private-key/);
      return true;
    });
    output.write(JSON.stringify({ type: "response", id: command.id, command: "prompt", success: false, error: "No API key: private-key" }) + "\n");
    await rejected;
    output.write(JSON.stringify({ type: "extension_error", event: "send_user_message", error: "private-key" }) + "\n");
    assert.deepEqual(errors, ["runtime_extension_error"]);
  } finally { rpc.close(); }
});

test("Worker RPC skips oversized event lines and never retries an uncertain prompt", async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const rpc = new WorkerRpc(input, output, () => {}, 10);
  try {
    const pending = rpc.prompt("once", false);
    input.read();
    output.write("x".repeat(100_000));
    output.write("\nnot-json\n");
    await assert.rejects(pending, { code: "command_ambiguous" });
    assert.equal(input.read(), null);
    const next = rpc.prompt("different", false);
    const command = JSON.parse(input.read().toString());
    output.write(JSON.stringify({ type: "response", id: command.id, command: "prompt", success: true }) + "\n");
    await next;
    const interrupted = rpc.prompt("closing", false);
    rpc.close();
    await assert.rejects(interrupted, { code: "command_ambiguous" });
  } finally { rpc.close(); }
});

test("model receipt binds both command and request, preserving model-specific errors", async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const rpc = new WorkerRpc(input, output, () => {});
  try {
    let accepted = false;
    const pending = rpc.setModel("test", "second").then((data) => { accepted = true; return data; });
    const command = JSON.parse(input.read().toString());
    output.write(JSON.stringify({type: "response", id: command.id, command: "prompt", success: true}) + "\n");
    await Promise.resolve();
    assert.equal(accepted, false);
    output.write(JSON.stringify({type: "response", id: command.id, command: "set_model", success: true,
      data: {provider: "test", id: "second"}}) + "\n");
    assert.deepEqual(await pending, {provider: "test", id: "second"});
    const rejected = rpc.setModel("test", "missing");
    const next = JSON.parse(input.read().toString());
    output.write(JSON.stringify({type: "response", id: next.id, command: "set_model", success: false,
      error: "private unexpected provider failure"}) + "\n");
    await assert.rejects(rejected, (error: any) => error.code === "model_check_failed" && !error.message.includes("private"));
  } finally { rpc.close(); }
});
