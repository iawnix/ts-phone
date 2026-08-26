import assert from "node:assert/strict";
import test from "node:test";
import { resolveConfig } from "../src/config.js";

test("configuration enforces a loopback-only listener", () => {
  const config = resolveConfig({}, "/tmp/ts-phone-config");
  assert.equal(config.host, "127.0.0.1");
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
