import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { BridgeIpcServer } from "./bridge/ipc-server.js";
import type { ServerConfig } from "./config.js";
import { HttpError, RuntimeError } from "./errors.js";
import { WorkspaceHub } from "./runtime/workspace-hub.js";
import { assertBearerAuthorization, ensureBearerToken, ensureBridgeSecret } from "./security.js";
import {
  API_VERSION,
  type ApprovalInput,
  type MessagePageRequest,
  type PromptInput,
  type SessionCommandInput,
} from "./types.js";

const MAX_SSE_BUFFERED_BYTES = 16 * 1024 * 1024;

export interface TsPhoneHttpServer {
  listen(): Promise<AddressInfo>;
  close(): Promise<void>;
  server: Server;
  hub: WorkspaceHub;
  bridgeServer: BridgeIpcServer;
}

export async function createTsPhoneHttpServer(config: ServerConfig): Promise<TsPhoneHttpServer> {
  const [token, bridgeSecret] = await Promise.all([
    ensureBearerToken(config.stateDir),
    ensureBridgeSecret(config.bridgeSecretPath),
  ]);
  const hub = new WorkspaceHub(config, bridgeSecret);
  const bridgeServer = new BridgeIpcServer(config, (socket, registration) => hub.attachBridge(socket, registration));
  const server = createServer((request, response) => {
    void handleRequest(config, hub, token, request, response).catch((error) => sendError(response, error));
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 15_000;
  server.keepAliveTimeout = 65_000;

  return {
    server,
    hub,
    bridgeServer,
    listen: async () => {
      await bridgeServer.listen();
      try {
        return await new Promise<AddressInfo>((resolve, reject) => {
          const onError = (error: Error) => reject(error);
          server.once("error", onError);
          server.listen(config.port, config.host, () => {
            server.off("error", onError);
            const address = server.address();
            if (!address || typeof address === "string") {
              reject(new Error("TS Phone server did not bind a TCP address"));
              return;
            }
            resolve(address);
          });
        });
      } catch (error) {
        await bridgeServer.close();
        throw error;
      }
    },
    close: async () => {
      if (server.listening) {
        await new Promise<void>((resolve, reject) => {
          server.close((error) => error ? reject(error) : resolve());
          server.closeAllConnections();
        });
      }
      await bridgeServer.close();
      hub.close();
    },
  };
}

async function handleRequest(
  config: ServerConfig,
  hub: WorkspaceHub,
  token: string,
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  setSecurityHeaders(response);
  const method = request.method || "GET";
  const url = new URL(request.url || "/", "http://localhost");

  if (method === "GET" && url.pathname === "/healthz") {
    sendJson(response, 200, { ok: true, service: "ts-phone", version: API_VERSION });
    return;
  }
  assertBearerAuthorization(request.headers.authorization, token);
  if (method === "GET" && url.pathname === "/api/v3/version") {
    sendData(response, 200, { apiVersion: API_VERSION, serviceVersion: "0.4.1" });
    return;
  }
  if (method === "GET" && url.pathname === "/api/v3/workspaces") {
    sendData(response, 200, await hub.listWorkspaces());
    return;
  }

  const segments = decodeSegments(url.pathname);
  if (segments.length < 4 || segments[0] !== "api" || segments[1] !== "v3" || segments[2] !== "workspaces") {
    throw new HttpError(404, "not_found", "API endpoint was not found");
  }
  const workspaceId = segments[3] || "";
  const resource = segments[4];
  if (resource === undefined && method === "GET") {
    sendData(response, 200, await hub.getWorkspace(workspaceId));
    return;
  }
  if (resource !== "sessions") {
    throw new HttpError(404, "not_found", "API endpoint was not found");
  }
  if (segments.length === 5 && method === "GET") {
    sendData(response, 200, await hub.listSessions(workspaceId));
    return;
  }
  const sessionId = segments[5] || "";
  const sessionResource = segments[6];
  if (sessionResource === "messages" && segments.length === 7) {
    if (method === "GET") {
      sendData(response, 200, await hub.getMessages(workspaceId, sessionId, validateMessagePageRequest(url)));
      return;
    }
    if (method === "POST") {
      const input = validatePrompt(await readJsonBody(request, config.maxBodyBytes));
      await hub.prompt(workspaceId, sessionId, input);
      sendData(response, 202, { accepted: true, clientMessageId: input.clientMessageId });
      return;
    }
  }
  if (sessionResource === "abort" && segments.length === 7 && method === "POST") {
    const input = validateSessionCommand(await readJsonBody(request, config.maxBodyBytes));
    await hub.abort(workspaceId, sessionId, input);
    sendData(response, 200, { aborted: true });
    return;
  }
  if (sessionResource === "events" && segments.length === 7 && method === "GET") {
    await streamEvents(hub, workspaceId, sessionId, request, response);
    return;
  }
  if (sessionResource === "approvals" && segments.length === 8 && method === "POST") {
    const approvalId = segments[7] || "";
    const input = validateApproval(await readJsonBody(request, config.maxBodyBytes));
    await hub.respondToApproval(workspaceId, sessionId, approvalId, input);
    sendData(response, 202, { accepted: true });
    return;
  }
  throw new HttpError(404, "not_found", "API endpoint was not found");
}

function validateMessagePageRequest(url: URL): MessagePageRequest {
  for (const key of url.searchParams.keys()) {
    if (key !== "before" && key !== "limit") {
      throw new HttpError(400, "invalid_message_query", "Messages only accepts before and limit query parameters");
    }
  }
  if (url.searchParams.getAll("before").length > 1 || url.searchParams.getAll("limit").length > 1) {
    throw new HttpError(400, "invalid_message_query", "Message query parameters must not be repeated");
  }
  const rawBefore = url.searchParams.get("before");
  if (rawBefore !== null && !/^[0-9a-f]{8}$/.test(rawBefore)) {
    throw new HttpError(400, "invalid_message_cursor", "Message cursor is invalid");
  }
  const rawLimit = url.searchParams.get("limit");
  if (rawLimit !== null && !/^[1-9][0-9]*$/.test(rawLimit)) {
    throw new HttpError(400, "invalid_message_limit", "Message page limit must be between 1 and 500");
  }
  const limit = rawLimit === null ? 500 : Number(rawLimit);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 500) {
    throw new HttpError(400, "invalid_message_limit", "Message page limit must be between 1 and 500");
  }
  return { ...(rawBefore === null ? {} : { before: rawBefore }), limit };
}

function decodeSegments(pathname: string): string[] {
  try {
    return pathname.split("/").filter(Boolean).map((segment) => decodeURIComponent(segment));
  } catch {
    throw new HttpError(400, "invalid_path", "API path is not valid UTF-8 encoding");
  }
}

async function readJsonBody(request: IncomingMessage, limit: number): Promise<unknown> {
  const contentType = request.headers["content-type"]?.split(";", 1)[0]?.trim();
  if (contentType !== "application/json") {
    throw new HttpError(415, "unsupported_media_type", "Content-Type must be application/json");
  }
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) {
      request.resume();
      throw new HttpError(413, "body_too_large", "Request body exceeded the configured limit");
    }
    chunks.push(buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new HttpError(400, "invalid_json", "Request body must be valid JSON");
  }
}

function validatePrompt(value: unknown): PromptInput {
  if (!isObject(value)
    || typeof value.message !== "string"
    || typeof value.clientMessageId !== "string"
    || typeof value.sessionRevision !== "string") {
    throw new HttpError(400, "invalid_prompt", "message, clientMessageId, and sessionRevision must be strings");
  }
  const keys = Object.keys(value);
  if (keys.some((key) => key !== "message" && key !== "clientMessageId" && key !== "sessionRevision")) {
    throw new HttpError(400, "invalid_prompt", "Prompt contained an unsupported field");
  }
  const message = value.message.trim();
  if (message.length === 0 || message.length > 65_536) {
    throw new HttpError(400, "invalid_prompt", "message length must be between 1 and 65536 characters");
  }
  if (!/^[A-Za-z0-9._:-]{1,160}$/.test(value.clientMessageId)) {
    throw new HttpError(400, "invalid_prompt", "clientMessageId is invalid");
  }
  validateRevision(value.sessionRevision);
  return { message, clientMessageId: value.clientMessageId, sessionRevision: value.sessionRevision };
}

function validateApproval(value: unknown): ApprovalInput {
  if (!isObject(value)
    || Object.keys(value).length !== 2
    || typeof value.approved !== "boolean"
    || typeof value.sessionRevision !== "string") {
    throw new HttpError(400, "invalid_approval", "approved and sessionRevision are required");
  }
  validateRevision(value.sessionRevision);
  return { approved: value.approved, sessionRevision: value.sessionRevision };
}

function validateSessionCommand(value: unknown): SessionCommandInput {
  if (!isObject(value) || Object.keys(value).length !== 1 || typeof value.sessionRevision !== "string") {
    throw new HttpError(400, "invalid_request", "sessionRevision must be the only field");
  }
  validateRevision(value.sessionRevision);
  return { sessionRevision: value.sessionRevision };
}

function validateRevision(value: string): void {
  if (!/^[0-9a-f-]{36}$/.test(value)) {
    throw new HttpError(400, "invalid_session_revision", "sessionRevision is invalid");
  }
}

async function streamEvents(
  hub: WorkspaceHub,
  workspaceId: string,
  sessionId: string,
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  const journal = await hub.journal(workspaceId, sessionId);
  response.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  response.flushHeaders();
  const lastEventId = Array.isArray(request.headers["last-event-id"])
    ? request.headers["last-event-id"][0]
    : request.headers["last-event-id"];
  let unsubscribe = () => {};
  let heartbeat: NodeJS.Timeout | undefined;
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    if (heartbeat) clearInterval(heartbeat);
    unsubscribe();
    if (!response.writableEnded) response.end();
  };
  unsubscribe = journal.subscribe((event) => {
    if (!writeSse(response, event.type, event.id, event)) close();
  });
  request.once("close", close);
  for (const event of journal.since(lastEventId)) {
    if (!writeSse(response, event.type, event.id, event)) {
      close();
      return;
    }
  }
  heartbeat = setInterval(() => {
    response.write(": heartbeat\n\n");
    if (response.writableLength > MAX_SSE_BUFFERED_BYTES) close();
  }, 15_000);
  heartbeat.unref();
}

function writeSse(response: ServerResponse, type: string, id: string, value: unknown): boolean {
  response.write(`id: ${id}\nevent: ${safeEventName(type)}\ndata: ${JSON.stringify(value)}\n\n`);
  return response.writableLength <= MAX_SSE_BUFFERED_BYTES;
}

function safeEventName(value: string): string {
  return /^[A-Za-z0-9_.-]{1,100}$/.test(value) ? value : "pi_event";
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function sendData(response: ServerResponse, status: number, data: unknown): void {
  sendJson(response, status, { apiVersion: API_VERSION, data });
}

function sendError(response: ServerResponse, error: unknown): void {
  if (response.headersSent) {
    if (!response.writableEnded) response.end();
    return;
  }
  if (error instanceof HttpError) {
    sendJson(response, error.status, { apiVersion: API_VERSION, error: { code: error.code, message: error.message } });
    return;
  }
  if (error instanceof RuntimeError) {
    const status = error.code === "command_ambiguous" ? 504 : 502;
    sendJson(response, status, { apiVersion: API_VERSION, error: { code: error.code, message: error.message } });
    return;
  }
  sendJson(response, 500, {
    apiVersion: API_VERSION,
    error: { code: "internal_error", message: "Internal server error" },
  });
}

function setSecurityHeaders(response: ServerResponse): void {
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("X-Frame-Options", "DENY");
  response.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
}

function sendJson(response: ServerResponse, status: number, value: unknown): void {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
  });
  response.end(body);
}
