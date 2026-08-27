import assert from "node:assert/strict";
import test from "node:test";
import { parseServerCommand, SERVER_USAGE } from "../src/server-command.js";

test("server command starts only when no arguments are provided", () => {
  assert.equal(parseServerCommand([]), "start");
  assert.throws(
    () => parseServerCommand(["--port", "22114"]),
    /does not accept positional arguments or runtime options/,
  );
});

test("server command exposes side-effect-free help aliases", () => {
  for (const argument of ["help", "--help", "-h"]) {
    assert.equal(parseServerCommand([argument]), "help");
  }
  assert.match(SERVER_USAGE, /^Usage:\n  ts-phone-server/m);
});
