import { randomUUID } from "node:crypto";
import type { Socket } from "node:net";
import { RuntimeError } from "../errors.js";
import type {
  BridgeClientRecord,
  BridgeCommandAckRecord,
  BridgeRegisterRecord,
  BridgeServerRecord,
} from "./protocol.js";
import { BRIDGE_PROTOCOL_VERSION } from "./protocol.js";
import type { SessionAccessMode } from "../types.js";

interface PendingCommand {
  resolve: () => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
}

export type BridgeRecordListener = (record: Exclude<BridgeClientRecord, BridgeRegisterRecord | BridgeCommandAckRecord>) => void;
type BridgeCommandRecord = Extract<BridgeServerRecord, { requestId: string }>;
type BridgeCommandInput = BridgeCommandRecord extends infer T
  ? T extends BridgeCommandRecord ? Omit<T, "requestId"> : never
  : never;

export class BridgeConnection {
  readonly workspaceId: string;
  readonly workspaceRoot: string;
  readonly sessionId: string;
  readonly accessMode: SessionAccessMode;
  readonly instanceEpoch: string;
  readonly pid: number;
  readonly #socket: Socket;
  readonly #commandTimeoutMs: number;
  readonly #pending = new Map<string, PendingCommand>();
  readonly #recordListeners = new Set<BridgeRecordListener>();
  readonly #closeListeners = new Set<() => void>();
  #sessionGeneration: number;
  #lastSequence = 0;
  #lastSeenAt = Date.now();
  #closed = false;

  constructor(socket: Socket, registration: BridgeRegisterRecord, commandTimeoutMs: number) {
    this.#socket = socket;
    this.#commandTimeoutMs = commandTimeoutMs;
    this.workspaceId = registration.workspaceId;
    this.workspaceRoot = registration.workspaceRoot;
    this.sessionId = registration.sessionId;
    this.accessMode = registration.accessMode;
    this.instanceEpoch = registration.instanceEpoch;
    this.pid = registration.pid;
    this.#sessionGeneration = registration.sessionGeneration;
    socket.once("close", () => this.#handleClose());
    socket.once("error", () => this.#handleClose());
  }

  get sessionGeneration(): number {
    return this.#sessionGeneration;
  }

  get lastSeenAt(): number {
    return this.#lastSeenAt;
  }

  get closed(): boolean {
    return this.#closed || this.#socket.destroyed;
  }

  onRecord(listener: BridgeRecordListener): () => void {
    this.#recordListeners.add(listener);
    return () => this.#recordListeners.delete(listener);
  }

  onClose(listener: () => void): () => void {
    if (this.closed) {
      listener();
      return () => {};
    }
    this.#closeListeners.add(listener);
    return () => this.#closeListeners.delete(listener);
  }

  accept(record: BridgeClientRecord): void {
    if (record.type === "bridge.register") throw new Error("Bridge connection attempted to register twice");
    if (record.workspaceId !== this.workspaceId
      || record.sessionId !== this.sessionId
      || record.instanceEpoch !== this.instanceEpoch) {
      throw new Error("Bridge record identity changed after registration");
    }
    this.#lastSeenAt = Date.now();
    if (record.type === "command.ack") {
      if (record.sessionGeneration !== this.#sessionGeneration) return;
      this.#handleAck(record);
      return;
    }
    if (record.sessionGeneration !== this.#sessionGeneration) {
      throw new Error("Bridge record changed session generation after registration");
    }
    if (record.sequence <= this.#lastSequence) throw new Error("Bridge event sequence did not increase");
    this.#lastSequence = record.sequence;
    for (const listener of this.#recordListeners) listener(record);
  }

  acknowledgeRegistration(): void {
    this.#write({
      protocolVersion: BRIDGE_PROTOCOL_VERSION,
      type: "bridge.registered",
      workspaceId: this.workspaceId,
      sessionId: this.sessionId,
      instanceEpoch: this.instanceEpoch,
    });
  }

  sendCommand(
    command: BridgeCommandInput,
  ): Promise<void> {
    if (this.closed) return Promise.reject(new RuntimeError("bridge_offline", "TSPi bridge is offline"));
    const requestId = randomUUID();
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#pending.delete(requestId);
        reject(new RuntimeError("command_ambiguous", "TSPi bridge command timed out; do not retry automatically"));
      }, this.#commandTimeoutMs);
      timer.unref();
      this.#pending.set(requestId, { resolve, reject, timer });
      try {
        this.#write({ ...command, requestId } as BridgeServerRecord);
      } catch (error) {
        clearTimeout(timer);
        this.#pending.delete(requestId);
        reject(error as Error);
      }
    });
  }

  close(): void {
    if (!this.#socket.destroyed) this.#socket.destroy();
    this.#handleClose();
  }

  #write(record: BridgeServerRecord): void {
    if (this.closed) throw new RuntimeError("bridge_offline", "TSPi bridge is offline");
    this.#socket.write(`${JSON.stringify(record)}\n`);
  }

  #handleAck(record: BridgeCommandAckRecord): void {
    const pending = this.#pending.get(record.requestId);
    if (!pending) return;
    clearTimeout(pending.timer);
    this.#pending.delete(record.requestId);
    if (record.ok) pending.resolve();
    else pending.reject(new RuntimeError(record.errorCode || "bridge_command_failed", "TSPi rejected the command"));
  }

  #handleClose(): void {
    if (this.#closed) return;
    this.#closed = true;
    const error = new RuntimeError("bridge_disconnected", "TSPi bridge disconnected before command acknowledgement");
    for (const pending of this.#pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.#pending.clear();
    for (const listener of this.#closeListeners) listener();
    this.#recordListeners.clear();
    this.#closeListeners.clear();
  }
}
