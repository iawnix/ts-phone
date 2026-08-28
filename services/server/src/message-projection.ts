export const MAX_SNAPSHOT_MESSAGES = 500;
export const MAX_SNAPSHOT_BYTES = 6 * 1024 * 1024;

export interface ProjectedMessageRecord {
  id: string;
  message: unknown;
}

export function projectSnapshotMessages(messages: unknown[]): unknown[] {
  return boundProjectedMessages(messages.flatMap((message) => {
    const projected = projectMessage(message);
    return projected === undefined ? [] : [projected];
  }));
}

export function projectSnapshotMessagePage(
  messages: unknown[],
  messageIds?: string[],
): { messages: unknown[]; messageIds?: string[]; omitted: number } {
  if (messageIds === undefined) {
    const projected = messages.flatMap((message) => {
      const value = projectMessage(message);
      return value === undefined ? [] : [value];
    });
    const bounded = boundProjectedMessages(projected);
    return { messages: bounded, omitted: projected.length - bounded.length };
  }
  const projected = messages.flatMap((message, index) => {
    const value = projectMessage(message);
    return value === undefined ? [] : [{ id: messageIds[index]!, message: value }];
  });
  const bounded = boundProjectedMessageRecords(projected);
  return {
    messages: bounded.records.map((record) => record.message),
    messageIds: bounded.records.map((record) => record.id),
    omitted: bounded.omitted,
  };
}

export function appendProjectedMessage(messages: unknown[], message: unknown): unknown[] {
  const projected = projectMessage(message);
  return projected === undefined
    ? messages
    : boundProjectedMessages([...messages, projected]);
}

export function boundProjectedMessages(messages: unknown[]): unknown[] {
  return boundProjectedMessageRecords(messages.map((message, index) => ({
    id: String(index),
    message,
  }))).records.map((record) => record.message);
}

export function boundProjectedMessageRecords(
  records: readonly ProjectedMessageRecord[],
  limit = MAX_SNAPSHOT_MESSAGES,
): { records: ProjectedMessageRecord[]; omitted: number } {
  const maximum = Math.max(0, Math.min(limit, records.length));
  let start = records.length;
  let serializedBytes = 2; // JSON array brackets.
  while (start > records.length - maximum) {
    const record = records[start - 1]!;
    const messageBytes = Buffer.byteLength(JSON.stringify(record.message) ?? "null");
    const nextBytes = serializedBytes + messageBytes + (start < records.length ? 1 : 0);
    if (nextBytes > MAX_SNAPSHOT_BYTES) break;
    serializedBytes = nextBytes;
    start -= 1;
  }
  const bounded = records.slice(start);
  return { records: bounded, omitted: records.length - bounded.length };
}

// Keep this projection aligned with the TSPi ts-phone bridge. It is the
// boundary that prevents raw Pi session records from reaching the phone.
export function projectMessage(message: unknown): unknown | undefined {
  if (!message || typeof message !== "object" || Array.isArray(message)) return undefined;
  const candidate = message as Record<string, unknown>;
  if (candidate.role === "user") {
    return {
      role: candidate.role,
      content: projectContent(candidate.content, 256 * 1024),
      timestamp: candidate.timestamp,
    };
  }
  if (candidate.role === "assistant" && Array.isArray(candidate.content)) {
    const content: Array<Record<string, unknown>> = [];
    for (const value of candidate.content) {
      if (!value || typeof value !== "object" || Array.isArray(value)) continue;
      const block = value as Record<string, unknown>;
      if (block.type === "text" && typeof block.text === "string") {
        content.push({ type: "text", text: boundText(block.text, 256 * 1024) });
        continue;
      }
      if (block.type === "toolCall" && typeof block.name === "string") {
        content.push({ type: "toolCall", name: block.name, arguments: block.arguments });
      }
    }
    return { role: candidate.role, content, timestamp: candidate.timestamp };
  }
  if (candidate.role === "toolResult") {
    return {
      role: candidate.role,
      toolCallId: candidate.toolCallId,
      toolName: candidate.toolName,
      content: projectContent(candidate.content, 128 * 1024),
      isError: candidate.isError,
      timestamp: candidate.timestamp,
    };
  }
  return undefined;
}

function projectContent(content: unknown, maxText: number): unknown {
  if (typeof content === "string") return boundText(content, maxText);
  if (!Array.isArray(content)) return [];
  return content.flatMap((block) => {
    if (!block || typeof block !== "object" || Array.isArray(block)) return [];
    const candidate = block as { type?: unknown; text?: unknown };
    if (candidate.type === "text" && typeof candidate.text === "string") {
      return [{ type: "text", text: boundText(candidate.text, maxText) }];
    }
    return [];
  });
}

function boundText(value: string, max: number): string {
  return value.length <= max ? value : `${value.slice(0, max)}\n... [truncated by TS Phone]`;
}
