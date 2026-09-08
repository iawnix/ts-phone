import { randomUUID } from "node:crypto";
import type { Readable, Writable } from "node:stream";
import { HttpError, RuntimeError } from "../errors.js";

const MAX_RESPONSE_BYTES = 64 * 1024;

export function promptFailure(error: unknown): HttpError {
  const text = typeof error === "string" ? error : "";
  if (/\b(?:EROFS|EACCES|EPERM|ELOCKED)\b|read-only file system|model_storage_unavailable/i.test(text)) {
    return new HttpError(409, "model_storage_unavailable", "TSPi cannot access its model credential or cache storage");
  }
  if (/no api key|api key.*not found|authentication|credentials|\bmodel_auth_missing\b/i.test(text)) {
    return new HttpError(409, "model_auth_missing", "The selected model has no usable authentication on the TSPi host");
  }
  if (/no model|model.*not found|unknown model|\bmodel_unavailable\b/i.test(text)) {
    return new HttpError(409, "model_unavailable", "No usable model is selected in this TSPi session");
  }
  if (/\bmodel_check_failed\b/i.test(text)) {
    return new HttpError(409, "model_check_failed", "TSPi could not check the selected model");
  }
  // Provider and extension errors may contain keys, URLs, or request bodies.
  return new HttpError(409, "prompt_rejected", "Pi rejected this message before model execution");
}

/** Only Pi's request-correlated preflight response acknowledges a prompt. */
export class WorkerRpc {
  readonly #pending = new Map<string, {
    resolve: () => void;
    reject: (error: Error) => void;
    timer: NodeJS.Timeout;
  }>();
  #buffer = Buffer.alloc(0);
  #skippingLine = false;
  #closed = false;

  constructor(
    readonly input: Writable,
    output: Readable,
    readonly onExtensionError: (error: HttpError) => void,
    readonly timeoutMs = 30_000,
  ) {
    output.on("data", (chunk: Buffer | string) => this.#read(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
    output.on("end", () => this.close());
    input.on("error", () => this.close());
  }

  prompt(message: string, followUp: boolean): Promise<void> {
    if (this.#closed) return Promise.reject(new HttpError(409, "session_offline", "TSPi Worker is offline"));
    const id = randomUUID();
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#pending.delete(id);
        reject(new RuntimeError("command_ambiguous", "Pi prompt receipt timed out; do not resend automatically"));
      }, this.timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      this.input.write(`${JSON.stringify({ id, type: "prompt", message, ...(followUp ? { streamingBehavior: "followUp" } : {}) })}\n`,
        (error) => { if (error) this.close(); });
    });
  }

  close(): void {
    this.#closed = true;
    this.#buffer = Buffer.alloc(0);
    for (const request of this.#pending.values()) {
      clearTimeout(request.timer);
      request.reject(new RuntimeError("command_ambiguous", "Worker closed before acknowledging the prompt"));
    }
    this.#pending.clear();
  }

  #read(chunk: Buffer): void {
    let start = 0;
    while (start < chunk.length) {
      const newline = chunk.indexOf(10, start);
      const end = newline < 0 ? chunk.length : newline;
      if (!this.#skippingLine) {
        if (this.#buffer.length + end - start > MAX_RESPONSE_BYTES) {
          this.#buffer = Buffer.alloc(0);
          this.#skippingLine = true;
        } else {
          this.#buffer = Buffer.concat([this.#buffer, chunk.subarray(start, end)]);
        }
      }
      if (newline < 0) break;
      if (!this.#skippingLine) this.#record(this.#buffer.toString("utf8"));
      this.#buffer = Buffer.alloc(0);
      this.#skippingLine = false;
      start = newline + 1;
    }
  }

  #record(line: string): void {
    let value: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(line);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return;
      value = parsed as Record<string, unknown>;
    } catch { return; }
    if (value.type === "extension_error") {
      this.onExtensionError(new HttpError(409, "runtime_extension_error", "An extension failed in the TSPi session"));
      return;
    }
    if (value.type !== "response" || value.command !== "prompt" || typeof value.id !== "string") return;
    const pending = this.#pending.get(value.id);
    if (!pending || typeof value.success !== "boolean") return;
    this.#pending.delete(value.id);
    clearTimeout(pending.timer);
    if (value.success) pending.resolve();
    else pending.reject(promptFailure(value.error));
  }
}
