import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { parseEnv } from "node:util";
import { resolveConfig } from "../src/config.js";

test("configuration enforces a loopback-only listener", () => {
  const config = resolveConfig({}, "/tmp/ts-phone-config");
  assert.equal(config.host, "127.0.0.1");
  assert.equal(config.workspaceRoot, "/tmp/ts-phone-config/workspaces");
  assert.equal(config.bridgeSocketPath, "/tmp/ts-phone-config/.runtime/runtime/bridge.sock");
  assert.equal(
    resolveConfig({ TS_PHONE_HOST: "::1" }, "/tmp/ts-phone-config").host,
    "::1",
  );
  assert.throws(
    () => resolveConfig({ TS_PHONE_HOST: "0.0.0.0" }, "/tmp/ts-phone-config"),
    /must be 127\.0\.0\.1 or ::1/,
  );
  assert.throws(
    () => resolveConfig({ TS_PHONE_HOST: "phone.example" }, "/tmp/ts-phone-config"),
    /must be 127\.0\.0\.1 or ::1/,
  );
});

test("configuration keeps the local bridge capability separate from the public token", () => {
  assert.throws(
    () => resolveConfig({
      TS_PHONE_STATE_DIR: "/tmp/ts-phone-config/state",
      TS_PHONE_BRIDGE_SECRET_FILE: "/tmp/ts-phone-config/state/auth.token",
    }, "/tmp/ts-phone-config"),
    /must differ from the public Bearer token file/,
  );
});

test("the distributed example does not bind another user's installation or UID", () => {
  const example = parseEnv(readFileSync(new URL("../../../deploy/server.env.example", import.meta.url), "utf8"));
  const config = resolveConfig(example, "/tmp/another-phone-installation");
  assert.equal(config.tspiPath, undefined);
  assert.equal(config.workspaceRoot, "/tmp/another-phone-installation/workspaces");
  assert.equal(config.stateDir, "/tmp/another-phone-installation/.runtime");
  assert.equal(config.bridgeSocketPath, "/tmp/another-phone-installation/.runtime/runtime/bridge.sock");
  assert.equal(config.bridgeSecretPath, "/tmp/another-phone-installation/.runtime/bridge.secret");
});
