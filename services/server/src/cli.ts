#!/usr/bin/env node

import { resolveConfig } from "./config.js";
import { ensureBearerToken, readBearerToken } from "./security.js";

const config = resolveConfig();
const [command, argument] = process.argv.slice(2);

if (!command || command === "help" || command === "--help" || command === "-h") {
  process.stdout.write(`Usage:\n  ts-phone-ctl token\n  ts-phone-ctl workspaces\n  ts-phone-ctl status <workspace>\n`);
  process.exit(0);
}

if (command === "token") {
  await ensureBearerToken(config.stateDir);
  process.stdout.write(`${await readBearerToken(config.stateDir)}\n`);
  process.exit(0);
}

const token = await readBearerToken(config.stateDir);
const baseUrl = `http://${config.host}:${config.port}/api/v4`;

if (command === "workspaces") {
  const response = await apiRequest(`${baseUrl}/workspaces`, token, "GET");
  process.stdout.write(`${JSON.stringify(response, null, 2)}\n`);
  process.exit(0);
}

if (command === "status" && argument) {
  const response = await apiRequest(`${baseUrl}/workspaces/${encodeURIComponent(argument)}`, token, "GET");
  process.stdout.write(`${JSON.stringify(response, null, 2)}\n`);
  process.exit(0);
}

process.stderr.write("Invalid TS Phone control command\n");
process.exit(2);

async function apiRequest(url: string, token: string, method: string): Promise<unknown> {
  const response = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}` },
  });
  const payload = await response.json() as unknown;
  if (!response.ok) {
    throw new Error(`TS Phone API returned ${response.status}: ${JSON.stringify(payload)}`);
  }
  return payload;
}
