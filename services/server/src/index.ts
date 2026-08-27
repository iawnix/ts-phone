#!/usr/bin/env node

import { resolveConfig } from "./config.js";
import { createTsPhoneHttpServer } from "./http-server.js";
import { parseServerCommand, SERVER_USAGE } from "./server-command.js";

const command = parseServerCommand(process.argv.slice(2));

if (command === "help") {
  process.stdout.write(SERVER_USAGE);
} else {
  const config = resolveConfig();
  const application = await createTsPhoneHttpServer(config);
  const address = await application.listen();
  process.stdout.write(`TS Phone listening on http://${address.address}:${address.port}\n`);
  process.stdout.write(`TSPi bridge socket: ${config.bridgeSocketPath}\n`);
  process.stdout.write(`Local token file: ${config.stateDir}/auth.token\n`);

  let shuttingDown = false;
  const shutdown = async () => {
    if (shuttingDown) return;
    shuttingDown = true;
    await application.close();
  };

  process.on("SIGTERM", () => void shutdown());
  process.on("SIGINT", () => void shutdown());
}
