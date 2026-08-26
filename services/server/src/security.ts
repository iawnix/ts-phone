import { randomBytes, timingSafeEqual } from "node:crypto";
import { constants } from "node:fs";
import { chmod, lstat, mkdir, open, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { HttpError } from "./errors.js";

const TOKEN_BYTES = 32;
const TOKEN_FILE = "auth.token";

export async function ensureBearerToken(stateDir: string): Promise<string> {
  return ensureSecureToken(join(stateDir, TOKEN_FILE));
}

export async function ensureBridgeSecret(path: string): Promise<string> {
  return ensureSecureToken(path);
}

async function ensureSecureToken(path: string): Promise<string> {
  const parent = dirname(path);
  await mkdir(parent, { recursive: true, mode: 0o700 });
  const stateStat = await lstat(parent);
  if (!stateStat.isDirectory() || stateStat.isSymbolicLink()) {
    throw new Error("TS Phone state directory must be a real directory");
  }
  if (typeof process.getuid === "function" && stateStat.uid !== process.getuid()) {
    throw new Error("TS Phone state directory must be owned by the service user");
  }
  await chmod(parent, 0o700);

  try {
    return await readSecureToken(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }

  const token = randomBytes(TOKEN_BYTES).toString("base64url");
  let handle;
  try {
    handle = await open(path, "wx", 0o600);
    await writeFile(handle, `${token}\n`, "utf8");
    await handle.sync();
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") {
      return readSecureToken(path);
    }
    throw error;
  } finally {
    await handle?.close();
  }
  return token;
}

export async function readBearerToken(stateDir: string): Promise<string> {
  return readSecureToken(join(stateDir, TOKEN_FILE));
}

export async function readBridgeSecret(path: string): Promise<string> {
  return readSecureToken(path);
}

async function readSecureToken(path: string): Promise<string> {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) throw new Error("TS Phone token must be a regular file");
    if (typeof process.getuid === "function" && stat.uid !== process.getuid()) {
      throw new Error("TS Phone token must be owned by the service user");
    }
    if ((stat.mode & 0o077) !== 0) await handle.chmod(0o600);
    return normalizeToken(await handle.readFile("utf8"));
  } finally {
    await handle.close();
  }
}

function normalizeToken(raw: string): string {
  const token = raw.trim();
  if (!/^[A-Za-z0-9_-]{40,100}$/.test(token)) {
    throw new Error("TS Phone token file is invalid");
  }
  return token;
}

export function assertBearerAuthorization(header: string | undefined, expectedToken: string): void {
  if (!header?.startsWith("Bearer ")) {
    throw new HttpError(401, "authentication_required", "Bearer authentication is required");
  }
  const provided = Buffer.from(header.slice(7), "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    throw new HttpError(401, "authentication_failed", "Bearer authentication failed");
  }
}

export function secretsEqual(provided: string, expected: string): boolean {
  const providedBytes = Buffer.from(provided, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  return providedBytes.length === expectedBytes.length && timingSafeEqual(providedBytes, expectedBytes);
}
