import { randomUUID } from "node:crypto";
import { EVENT_VERSION, type EventEnvelope } from "./types.js";

export type EventListener = (event: EventEnvelope) => void;

export interface EventReplay {
  events: EventEnvelope[];
  /** True when the cursor cannot describe a complete retained event window. */
  needsSnapshot: boolean;
}

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
  #latestSnapshot: EventEnvelope | undefined;
  #latestState: EventEnvelope | undefined;

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

  /**
   * The last session snapshot is kept even when the bounded delivery cache
   * has evicted its event. It is a recovery baseline, not a second source of
   * conversation truth.
   */
  get latestSnapshot(): EventEnvelope | undefined {
    return this.#latestSnapshot;
  }

  /** Latest lightweight state baseline for sessions without a live snapshot. */
  get latestState(): EventEnvelope | undefined {
    return this.#latestState;
  }

  /**
   * Build a current checkpoint for a reconnect. The checkpoint advances to
   * the journal tail so events already represented by its payload are not
   * replayed a second time after a snapshot.
   */
  get latestBaseline(): EventEnvelope | undefined {
    const source = this.#latestSnapshot ?? this.#latestState;
    if (!source || this.#sequence === 0) return undefined;
    return {
      ...source,
      id: this.latestId,
      at: new Date().toISOString(),
    };
  }

  reset(): void {
    this.#epoch = randomUUID();
    this.#events.length = 0;
    this.#sizes.length = 0;
    this.#totalBytes = 0;
    this.#sequence = 0;
    this.#latestSnapshot = undefined;
    this.#latestState = undefined;
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
    if (type === "session.snapshot") this.#latestSnapshot = event;
    if (type === "session_state") this.#latestState = event;
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

  /** Refresh the retained snapshot payload without adding a delivery event. */
  refreshLatestSnapshot(payload: unknown): void {
    const current = this.#latestSnapshot;
    if (!current) return;
    // Delivery events are immutable history. Keep the refreshed payload only
    // as the out-of-band recovery baseline; replacing an event already in the
    // bounded journal would make a previously delivered snapshot change under
    // a reconnecting client and would invalidate replay assertions.
    const next: EventEnvelope = {
      ...current,
      payload,
      at: new Date().toISOString(),
    };
    this.#latestSnapshot = next;
  }

  since(lastEventId: string | undefined): EventEnvelope[] {
    if (!lastEventId) return [...this.#events];
    const [epoch, sequenceText] = lastEventId.split(":");
    if (epoch !== this.#epoch) return [...this.#events];
    const sequence = Number(sequenceText);
    if (!Number.isSafeInteger(sequence) || sequence < 0) return [...this.#events];
    return this.#events.filter((event) => Number(event.id.slice(event.id.lastIndexOf(":") + 1)) > sequence);
  }

  /**
   * Return a replay window and explicitly report cursor gaps. `since()` is
   * retained for callers that intentionally accept a best-effort bounded
   * window; SSE needs to know when a full snapshot is required first.
   */
  replay(lastEventId: string | undefined): EventReplay {
    if (!lastEventId) return { events: [...this.#events], needsSnapshot: false };
    const [epoch, sequenceText] = lastEventId.split(":");
    const sequence = Number(sequenceText);
    if (epoch !== this.#epoch || !Number.isSafeInteger(sequence) || sequence < 0) {
      return { events: [...this.#events], needsSnapshot: true };
    }
    const oldest = this.#events[0];
    const oldestSequence = oldest
      ? Number(oldest.id.slice(oldest.id.lastIndexOf(":") + 1))
      : this.#sequence + 1;
    const needsSnapshot = sequence > this.#sequence || sequence < oldestSequence - 1;
    return {
      events: this.#events.filter((event) => Number(event.id.slice(event.id.lastIndexOf(":") + 1)) > sequence),
      needsSnapshot,
    };
  }

  subscribe(listener: EventListener): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }
}
