import { chmod, lstat, mkdir, unlink } from "node:fs/promises";
import { createConnection, createServer, type Server, type Socket } from "node:net";
import { dirname } from "node:path";
import type { ServerConfig } from "../config.js";
import { attachStrictJsonlReader } from "./jsonl.js";
import { parseBridgeClientRecord, type BridgeRegisterRecord } from "./protocol.js";
import type { BridgeConnection } from "./bridge-connection.js";

export type BridgeRegistrar = (socket: Socket, registration: BridgeRegisterRecord) => Promise<BridgeConnection>;

export class BridgeIpcServer {
  readonly #config: ServerConfig;
  readonly #register: BridgeRegistrar;
  readonly #server: Server;
  readonly #connections = new Set<BridgeConnection>();

  constructor(config: ServerConfig, register: BridgeRegistrar) {
    this.#config = config;
    this.#register = register;
    this.#server = createServer((socket) => this.#acceptSocket(socket));
  }

  async listen(): Promise<void> {
    await prepareSocketPath(this.#config.bridgeSocketPath);
    await new Promise<void>((resolve, reject) => {
      const onError = (error: Error) => reject(error);
      this.#server.once("error", onError);
      this.#server.listen(this.#config.bridgeSocketPath, () => {
        this.#server.off("error", onError);
        resolve();
      });
    });
    await chmod(this.#config.bridgeSocketPath, 0o600);
  }

  async close(): Promise<void> {
    for (const connection of this.#connections) connection.close();
    this.#connections.clear();
    if (this.#server.listening) {
      await new Promise<void>((resolve, reject) => this.#server.close((error) => error ? reject(error) : resolve()));
    }
    try {
      await unlink(this.#config.bridgeSocketPath);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  #acceptSocket(socket: Socket): void {
    socket.setNoDelay(true);
    let connection: BridgeConnection | undefined;
    let registering = false;
    const registrationTimer = setTimeout(() => socket.destroy(), 5_000);
    registrationTimer.unref();
    const reader = attachStrictJsonlReader(
      socket,
      (value) => {
        try {
          const record = parseBridgeClientRecord(value);
          if (!connection) {
            if (record.type !== "bridge.register" || registering) throw new Error("First bridge record must register once");
            registering = true;
            void this.#register(socket, record).then((registered) => {
              if (socket.destroyed) {
                registered.close();
                return;
              }
              connection = registered;
              this.#connections.add(registered);
              clearTimeout(registrationTimer);
              registered.onClose(() => this.#connections.delete(registered));
              registered.acknowledgeRegistration();
            }).catch(() => socket.destroy());
            return;
          }
          connection.accept(record);
        } catch {
          socket.destroy();
        }
      },
      () => socket.destroy(),
      this.#config.bridgeMaxRecordBytes,
    );
    socket.once("close", () => {
      clearTimeout(registrationTimer);
      reader.close();
    });
  }
}

async function prepareSocketPath(path: string): Promise<void> {
  const parent = dirname(path);
  await mkdir(parent, { recursive: true, mode: 0o700 });
  const parentStat = await lstat(parent);
  if (!parentStat.isDirectory() || parentStat.isSymbolicLink()) {
    throw new Error("TS Phone bridge socket directory must be a real directory");
  }
  if (typeof process.getuid === "function" && parentStat.uid !== process.getuid()) {
    throw new Error("TS Phone bridge socket directory must be owned by the service user");
  }
  await chmod(parent, 0o700);
  try {
    const stat = await lstat(path);
    if (!stat.isSocket()) throw new Error("TS Phone bridge socket path is occupied by a non-socket file");
    if (await socketAcceptsConnections(path)) throw new Error("Another TS Phone bridge server is already running");
    await unlink(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

function socketAcceptsConnections(path: string): Promise<boolean> {
  return new Promise((resolve) => {
    const probe = createConnection(path);
    const timer = setTimeout(() => {
      probe.destroy();
      resolve(false);
    }, 500);
    timer.unref();
    probe.once("connect", () => {
      clearTimeout(timer);
      probe.destroy();
      resolve(true);
    });
    probe.once("error", () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}
