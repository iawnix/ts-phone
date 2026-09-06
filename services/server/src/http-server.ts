import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { BridgeIpcServer } from "./bridge/ipc-server.js";
import type { ServerConfig } from "./config.js";
import { HttpError, RuntimeError } from "./errors.js";
import { ManagementStore } from "./management-store.js";
import { WorkspaceHub } from "./runtime/workspace-hub.js";
import { WorkerSupervisor } from "./runtime/worker-supervisor.js";
import { assertBearerAuthorization, ensureBearerToken, ensureBridgeSecret } from "./security.js";
import {
  API_VERSION,
  SERVICE_VERSION,
  type AbortInput,
  type ApprovalInput,
  type CreateSessionInput,
  type CreateWorkspaceInput,
  type LifecycleInput,
  type LifecycleState,
  type MessagePageRequest,
  type PromptInput,
  type PurgeInput,
  type RenameInput,
  type TimelinePageRequest,
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
  const management = await ManagementStore.open(config.stateDir);
  const workers = new WorkerSupervisor(
    config.tspiPath,
    config.shutdownTimeoutMs,
    config.bridgeSocketPath,
    config.bridgeSecretPath,
  );
  const hub = new WorkspaceHub(config, bridgeSecret, management, workers);
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
      await hub.close();
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
  if (method === "GET" && url.pathname === "/api/v4/version") {
    sendData(response, 200, { apiVersion: API_VERSION, serviceVersion: SERVICE_VERSION });
    return;
  }
  if (method === "GET" && url.pathname === "/api/v4/workspaces") {
    sendData(response, 200, await hub.listWorkspaces(validateLifecycleQuery(url)));
    return;
  }
  if (method === "POST" && url.pathname === "/api/v4/workspaces") {
    const input = validateCreateWorkspace(await readJsonBody(request, config.maxBodyBytes));
    sendData(response, 201, await hub.createWorkspace(input));
    return;
  }

  const segments = decodeSegments(url.pathname);
  if (segments.length < 4 || segments[0] !== "api" || segments[1] !== "v4" || segments[2] !== "workspaces") {
    throw new HttpError(404, "not_found", "API endpoint was not found");
  }
  const workspaceId = segments[3] || "";
  const resource = segments[4];
  if (resource === undefined && method === "GET") {
    sendData(response, 200, await hub.getWorkspace(workspaceId));
    return;
  }
  if (resource === undefined && method === "PATCH") {
    const input = validateRename(await readJsonBody(request, config.maxBodyBytes));
    sendData(response, 200, await hub.renameWorkspace(workspaceId, input));
    return;
  }
  if (segments.length === 5 && method === "POST"
    && (resource === "archive" || resource === "restore" || resource === "trash" || resource === "purge")) {
    const input = await readJsonBody(request, config.maxBodyBytes);
    if (resource === "archive") {
      sendData(response, 200, await hub.archiveWorkspace(workspaceId, validateLifecycle(input)));
      return;
    }
    if (resource === "restore") {
      sendData(response, 200, await hub.restoreWorkspace(workspaceId, validateLifecycle(input)));
      return;
    }
    if (resource === "trash") {
      sendData(response, 200, await hub.trashWorkspace(workspaceId, validateLifecycle(input)));
      return;
    }
    if (resource === "purge") {
      await hub.purgeWorkspace(workspaceId, validatePurge(input));
      sendData(response, 200, { purged: true });
      return;
    }
  }
  if (resource === "deletion-preflight" && segments.length === 5 && method === "GET") {
    assertNoQuery(url, "Deletion preflight");
    sendData(response, 200, await hub.workspaceDeletionPreflight(workspaceId));
    return;
  }
  if (resource !== "sessions") {
    throw new HttpError(404, "not_found", "API endpoint was not found");
  }
  if (segments.length === 5 && method === "GET") {
    sendData(response, 200, await hub.listSessions(workspaceId, validateLifecycleQuery(url)));
    return;
  }
  if (segments.length === 5 && method === "POST") {
    const input = validateCreateSession(await readJsonBody(request, config.maxBodyBytes));
    sendData(response, 201, await hub.createSession(workspaceId, input));
    return;
  }
  const sessionId = segments[5] || "";
  const sessionResource = segments[6];
  if (sessionResource === undefined && segments.length === 6 && method === "PATCH") {
    const input = validateRename(await readJsonBody(request, config.maxBodyBytes));
    sendData(response, 200, await hub.renameSession(workspaceId, sessionId, input));
    return;
  }
  if (segments.length === 7 && method === "POST"
    && (sessionResource === "archive"
      || sessionResource === "restore"
      || sessionResource === "trash"
      || sessionResource === "purge"
      || sessionResource === "activate")) {
    const input = await readJsonBody(request, config.maxBodyBytes);
    if (sessionResource === "archive") {
      sendData(response, 200, await hub.archiveSession(workspaceId, sessionId, validateLifecycle(input)));
      return;
    }
    if (sessionResource === "restore") {
      sendData(response, 200, await hub.restoreSession(workspaceId, sessionId, validateLifecycle(input)));
      return;
    }
    if (sessionResource === "trash") {
      sendData(response, 200, await hub.trashSession(workspaceId, sessionId, validateLifecycle(input)));
      return;
    }
    if (sessionResource === "purge") {
      await hub.purgeSession(workspaceId, sessionId, validatePurge(input));
      sendData(response, 200, { purged: true });
      return;
    }
    if (sessionResource === "activate") {
      sendData(response, 200, await hub.activateSession(workspaceId, sessionId, validateLifecycle(input)));
      return;
    }
  }
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
  if (sessionResource === "timeline" && segments.length === 7 && method === "GET") {
    sendData(response, 200, await hub.getTimeline(
      workspaceId,
      sessionId,
      validateTimelinePageRequest(url),
    ));
    return;
  }
  if (sessionResource === "abort" && segments.length === 7 && method === "POST") {
    const input = validateAbort(await readJsonBody(request, config.maxBodyBytes));
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

function validateLifecycleQuery(url: URL): LifecycleState {
  for (const key of url.searchParams.keys()) {
    if (key !== "state") {
      throw new HttpError(400, "invalid_lifecycle_query", "List endpoints only accept the state query parameter");
    }
  }
  if (url.searchParams.getAll("state").length > 1) {
    throw new HttpError(400, "invalid_lifecycle_query", "The state query parameter must not be repeated");
  }
  const state = url.searchParams.get("state") ?? "active";
  if (state !== "active" && state !== "archived" && state !== "trashed") {
    throw new HttpError(400, "invalid_lifecycle_state", "state must be active, archived, or trashed");
  }
  return state;
}

function assertNoQuery(url: URL, label: string): void {
  if ([...url.searchParams.keys()].length > 0) {
    throw new HttpError(400, "invalid_query", `${label} does not accept query parameters`);
  }
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

function validateTimelinePageRequest(url: URL): TimelinePageRequest {
  for (const key of url.searchParams.keys()) {
    if (key !== "before" && key !== "limit" && key !== "branch") {
      throw new HttpError(
        400,
        "invalid_timeline_query",
        "Timeline only accepts before, limit, and branch query parameters",
      );
    }
  }
  for (const key of ["before", "limit", "branch"]) {
    if (url.searchParams.getAll(key).length > 1) {
      throw new HttpError(400, "invalid_timeline_query", "Timeline query parameters must not be repeated");
    }
  }
  const rawBefore = url.searchParams.get("before");
  const rawBranch = url.searchParams.get("branch");
  if (rawBefore !== null && !/^[0-9a-f]{8}$/.test(rawBefore)) {
    throw new HttpError(400, "invalid_timeline_cursor", "Timeline cursor is invalid");
  }
  if (rawBranch !== null && !/^[0-9a-f]{8}$/.test(rawBranch)) {
    throw new HttpError(400, "invalid_timeline_branch", "Timeline branch is invalid");
  }
  const rawLimit = url.searchParams.get("limit");
  if (rawLimit !== null && !/^[1-9][0-9]*$/.test(rawLimit)) {
    throw new HttpError(400, "invalid_timeline_limit", "Timeline page limit must be between 1 and 500");
  }
  const limit = rawLimit === null ? 500 : Number(rawLimit);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 500) {
    throw new HttpError(400, "invalid_timeline_limit", "Timeline page limit must be between 1 and 500");
  }
  return {
    ...(rawBefore === null ? {} : { before: rawBefore }),
    ...(rawBranch === null ? {} : { branch: rawBranch }),
    limit,
  };
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

function validateCreateWorkspace(value: unknown): CreateWorkspaceInput {
  if (!isObject(value)
    || Object.keys(value).length !== 1
    || typeof value.name !== "string") {
    throw new HttpError(400, "invalid_workspace_create", "name is required and no other fields are accepted");
  }
  return { name: validateDisplayName(value.name) };
}

function validateCreateSession(value: unknown): CreateSessionInput {
  if (!isObject(value)) {
    throw new HttpError(400, "invalid_session_create", "Session input must be an object");
  }
  const keys = Object.keys(value);
  if (keys.some((key) => key !== "name" && key !== "model" && key !== "accessMode")
    || (value.name !== undefined && typeof value.name !== "string")
    || (value.model !== undefined && typeof value.model !== "string")
    || (value.accessMode !== "controller" && value.accessMode !== "observer")) {
    throw new HttpError(400, "invalid_session_create", "accessMode is required; name and model are optional");
  }
  return {
    accessMode: value.accessMode,
    ...(value.name === undefined ? {} : { name: validateDisplayName(value.name) }),
    ...(value.model === undefined ? {} : { model: validateModel(value.model) }),
  };
}

function validateRename(value: unknown): RenameInput {
  if (!isObject(value)
    || Object.keys(value).length !== 2
    || typeof value.name !== "string"
    || typeof value.managementRevision !== "string") {
    throw new HttpError(400, "invalid_rename", "name and managementRevision are required");
  }
  return {
    name: validateDisplayName(value.name),
    managementRevision: validateManagementRevision(value.managementRevision),
  };
}

function validateLifecycle(value: unknown): LifecycleInput {
  if (!isObject(value)
    || Object.keys(value).length !== 1
    || typeof value.managementRevision !== "string") {
    throw new HttpError(400, "invalid_lifecycle_change", "managementRevision is required");
  }
  return { managementRevision: validateManagementRevision(value.managementRevision) };
}

function validatePurge(value: unknown): PurgeInput {
  if (!isObject(value)
    || Object.keys(value).length !== 2
    || typeof value.managementRevision !== "string"
    || typeof value.confirmation !== "string") {
    throw new HttpError(400, "invalid_purge", "managementRevision and confirmation are required");
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$/.test(value.confirmation)) {
    throw new HttpError(400, "invalid_purge_confirmation", "confirmation is invalid");
  }
  return {
    managementRevision: validateManagementRevision(value.managementRevision),
    confirmation: value.confirmation,
  };
}

function validateDisplayName(value: string): string {
  if (value.trim() !== value
    || value.length < 1
    || value.length > 120
    || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new HttpError(400, "invalid_display_name", "name must contain 1 to 120 visible characters without surrounding whitespace");
  }
  return value;
}

function validateModel(value: string): string {
  if (value.length < 1
    || value.length > 200
    || !/^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(value)) {
    throw new HttpError(400, "invalid_model", "model is invalid");
  }
  return value;
}

function validateManagementRevision(value: string): string {
  if (value !== "unmanaged" && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    throw new HttpError(400, "invalid_management_revision", "managementRevision is invalid");
  }
  return value;
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

function validateAbort(value: unknown): AbortInput {
  if (!isObject(value)
    || Object.keys(value).length !== 2
    || typeof value.sessionRevision !== "string"
    || typeof value.agentRunId !== "string") {
    throw new HttpError(400, "invalid_abort", "sessionRevision and agentRunId are required");
  }
  validateRevision(value.sessionRevision);
  if (!/^[A-Za-z0-9._:-]{1,160}$/.test(value.agentRunId)) {
    throw new HttpError(400, "invalid_agent_run_id", "agentRunId is invalid");
  }
  return { sessionRevision: value.sessionRevision, agentRunId: value.agentRunId };
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
    const status = error.code === "purge_recovery_failed"
      ? 500
      : error.code === "command_ambiguous"
        ? 504
        : (error.code === "agent_not_running" || error.code === "agent_run_stale" ? 409 : 502);
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
