import { HttpError } from "./errors.js";
import { MAX_SNAPSHOT_BYTES } from "./message-projection.js";
import type { MessagePageRequest } from "./types.js";

/** Page within one branch. Limits apply in both directions, including bytes. */
export function historyPage<T extends { id: string }>(
  records: readonly T[],
  request: MessagePageRequest,
): { records: T[]; hasMore: boolean; nextBefore?: string; hasLater: boolean; nextAfter?: string } {
  if ([request.before, request.after, request.edge].filter((value) => value !== undefined).length > 1) {
    throw new HttpError(400, "invalid_history_query", "Choose one history position");
  }
  const cursor = request.before ?? request.after;
  const index = cursor === undefined ? -1 : records.findIndex((record) => record.id === cursor);
  if (cursor !== undefined && index < 0) {
    throw new HttpError(409, "session_history_cursor_invalid", "History cursor is not present in this branch");
  }
  const forward = request.edge === "start" || request.after !== undefined;
  let start = forward ? (request.after === undefined ? 0 : index + 1) : (request.before === undefined ? records.length : index);
  let end = start;
  let bytes = 2;
  for (let count = 0; count < request.limit; count += 1) {
    const next = forward ? end : start - 1;
    if (next < 0 || next >= records.length) break;
    const size = Buffer.byteLength(JSON.stringify(records[next])) + 1;
    if (bytes + size > MAX_SNAPSHOT_BYTES) break;
    bytes += size;
    if (forward) end += 1;
    else start -= 1;
  }
  const page = records.slice(start, end);
  if (page.length === 0 && (forward ? end < records.length : start > 0)) {
    throw new HttpError(409, "session_history_unavailable", "History item exceeds the page limit");
  }
  const hasMore = start > 0 && page.length > 0;
  const hasLater = end < records.length && page.length > 0;
  return {
    records: page, hasMore, hasLater,
    ...(hasMore ? { nextBefore: page[0]!.id } : {}),
    ...(hasLater ? { nextAfter: page.at(-1)!.id } : {}),
  };
}
