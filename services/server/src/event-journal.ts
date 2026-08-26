import { randomUUID } from "node:crypto";
import { EVENT_VERSION, type EventEnvelope } from "./types.js";

export type EventListener = (event: EventEnvelope) => void;

export class EventJournal {
  #epoch = randomUUID();
  readonly #workspaceId: string;
  readonly #sessionId: string;
  readonly #capacity: number;
  readonly #maxBytes: number;
  readonly #events: EventEnvelope[] = [];
  readonly #sizes: number[] = [];
  readonly #listeners = new Set<EventListener>();
  #totalBytes = 0;
  #sequence = 0;

  constructor(workspaceId: string, sessionId: string, capacity: number, maxBytes: number) {
    this.#workspaceId = workspaceId;
    this.#sessionId = sessionId;
    this.#capacity = capacity;
    this.#maxBytes = maxBytes;
  }

  get epoch(): string {
    return this.#epoch;
  }

  get latestId(): string {
    return this.#events.at(-1)?.id ?? `${this.#epoch}:0`;
  }

  reset(): void {
    this.#epoch = randomUUID();
    this.#events.length = 0;
    this.#sizes.length = 0;
    this.#totalBytes = 0;
    this.#sequence = 0;
  }

  publish(
    type: string,
    payload: unknown,
    identity: { instanceEpoch: string; sessionGeneration: number } | undefined = undefined,
  ): EventEnvelope {
    this.#sequence += 1;
    const event: EventEnvelope = {
      protocolVersion: EVENT_VERSION,
      id: `${this.#epoch}:${this.#sequence}`,
      workspaceId: this.#workspaceId,
      sessionId: this.#sessionId,
      sessionRevision: this.#epoch,
      instanceEpoch: identity?.instanceEpoch ?? null,
      sessionGeneration: identity?.sessionGeneration ?? null,
      type,
      payload,
      at: new Date().toISOString(),
    };
    const size = Buffer.byteLength(JSON.stringify(event));
    this.#events.push(event);
    this.#sizes.push(size);
    this.#totalBytes += size;
    while (
      this.#events.length > 1
      && (this.#events.length > this.#capacity || this.#totalBytes > this.#maxBytes)
    ) {
      this.#events.shift();
      this.#totalBytes -= this.#sizes.shift()!;
    }
    for (const listener of this.#listeners) listener(event);
    return event;
  }

  since(lastEventId: string | undefined): EventEnvelope[] {
    if (!lastEventId) return [...this.#events];
    const [epoch, sequenceText] = lastEventId.split(":");
    if (epoch !== this.#epoch) return [...this.#events];
    const sequence = Number(sequenceText);
    if (!Number.isSafeInteger(sequence) || sequence < 0) return [...this.#events];
    return this.#events.filter((event) => Number(event.id.slice(event.id.lastIndexOf(":") + 1)) > sequence);
  }

  subscribe(listener: EventListener): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }
}
