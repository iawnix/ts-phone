import assert from "node:assert/strict";
import { chmod, mkdtemp, stat, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { HttpError } from "../src/errors.js";
import {
  assertBearerAuthorization,
  ensureBearerToken,
  ensureBridgeSecret,
  readBearerToken,
  readBridgeSecret,
} from "../src/security.js";

test("token is high entropy, persistent, and owner-only", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "ts-phone-security-"));
  const first = await ensureBearerToken(stateDir);
  const second = await ensureBearerToken(stateDir);
  assert.equal(first, second);
  assert.equal(first, await readBearerToken(stateDir));
  assert.ok(first.length >= 40);
  assert.equal((await stat(join(stateDir, "auth.token"))).mode & 0o777, 0o600);
  assert.doesNotThrow(() => assertBearerAuthorization(`Bearer ${first}`, first));
  assert.throws(() => assertBearerAuthorization("Bearer wrong", first), HttpError);
});

test("bridge capability is separate from the public Bearer token", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-bridge-secret-"));
  const bearer = await ensureBearerToken(root);
  const path = join(root, "bridge.secret");
  const bridge = await ensureBridgeSecret(path);
  assert.notEqual(bridge, bearer);
  assert.equal(await readBridgeSecret(path), bridge);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
});

test("token repairs permissive mode and rejects a symbolic-link state directory", async () => {
  const root = await mkdtemp(join(tmpdir(), "ts-phone-token-hardening-"));
  const stateDir = join(root, "state");
  const token = await ensureBearerToken(stateDir);
  const tokenPath = join(stateDir, "auth.token");
  await chmod(tokenPath, 0o644);
  assert.equal(await ensureBearerToken(stateDir), token);
  assert.equal((await stat(tokenPath)).mode & 0o777, 0o600);

  const linkedState = join(root, "linked-state");
  await writeFile(join(root, "outside-token"), `${token}\n`, "utf8");
  await symlink(root, linkedState);
  await assert.rejects(() => ensureBearerToken(linkedState), /real directory/);
});
