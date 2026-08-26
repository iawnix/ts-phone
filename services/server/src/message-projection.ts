export const MAX_SNAPSHOT_MESSAGES = 500;
export const MAX_SNAPSHOT_BYTES = 6 * 1024 * 1024;

export function projectSnapshotMessages(messages: unknown[]): unknown[] {
  return boundProjectedMessages(messages.flatMap((message) => {
    const projected = projectMessage(message);
    return projected === undefined ? [] : [projected];
  }));
}

export function appendProjectedMessage(messages: unknown[], message: unknown): unknown[] {
  const projected = projectMessage(message);
  return projected === undefined
    ? messages
    : boundProjectedMessages([...messages, projected]);
}

export function boundProjectedMessages(messages: unknown[]): unknown[] {
  const bounded = messages.slice(-MAX_SNAPSHOT_MESSAGES);
  while (bounded.length > 0 && Buffer.byteLength(JSON.stringify(bounded)) > MAX_SNAPSHOT_BYTES) {
    bounded.shift();
  }
  return bounded;
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
