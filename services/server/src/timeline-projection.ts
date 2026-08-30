import { MAX_SNAPSHOT_BYTES, projectMessage } from "./message-projection.js";
import type {
  TimelineActivity,
  TimelineBranchSummary,
  TimelineHistorySummary,
  TimelineItem,
} from "./types.js";

export interface SessionTimelineEntry {
  id: string;
  parentId: string | null;
  record: Record<string, unknown>;
}

export interface TimelineProjection {
  items: TimelineItem[];
  messageCount: number;
  activityCount: number;
  turnCount: number;
}

export interface BoundedTimelineProjection {
  items: TimelineItem[];
  omitted: number;
}

type TimelineActivityDraft = Pick<TimelineActivity, "category" | "status" | "title"> & {
  [Key in Exclude<keyof TimelineActivity, "category" | "status" | "title">]?:
    | TimelineActivity[Key]
    | undefined;
};

const MAX_ACTIVITY_REFS = 24;

export function projectTimeline(entries: readonly SessionTimelineEntry[]): TimelineProjection {
  const items: TimelineItem[] = [];
  let currentTurnId: string | undefined;
  let messageCount = 0;
  let activityCount = 0;
  let turnCount = 0;

  for (const entry of entries) {
    const record = entry.record;
    if (record.type === "message") {
      const message = projectMessage(record.message);
      if (message !== undefined) {
        if (messageRole(message) === "user") {
          currentTurnId = entry.id;
          turnCount += 1;
        }
        items.push({
          id: entry.id,
          kind: "message",
          ...(currentTurnId ? { turnId: currentTurnId } : {}),
          message,
        });
        messageCount += 1;
        continue;
      }
    }

    items.push({
      id: entry.id,
      kind: "activity",
      ...(currentTurnId ? { turnId: currentTurnId } : {}),
      activity: projectActivity(record),
    });
    activityCount += 1;
  }

  return { items, messageCount, activityCount, turnCount };
}

export function boundTimelineItems(
  items: readonly TimelineItem[],
  limit: number,
): BoundedTimelineProjection {
  const maximum = Math.max(0, Math.min(limit, items.length));
  let start = items.length;
  let serializedBytes = 2;
  while (start > items.length - maximum) {
    const itemBytes = Buffer.byteLength(JSON.stringify(items[start - 1]) ?? "null");
    const nextBytes = serializedBytes + itemBytes + (start < items.length ? 1 : 0);
    if (nextBytes > MAX_SNAPSHOT_BYTES) break;
    serializedBytes = nextBytes;
    start -= 1;
  }
  return { items: items.slice(start), omitted: start };
}

export function timelineHistorySummary(input: {
  activeBranchId?: string;
  selectedBranchId?: string;
  branches: TimelineBranchSummary[];
  projection: TimelineProjection;
}): TimelineHistorySummary {
  return {
    totalItems: input.projection.items.length,
    messageCount: input.projection.messageCount,
    activityCount: input.projection.activityCount,
    turnCount: input.projection.turnCount,
    branchCount: input.branches.length,
    ...(input.activeBranchId ? { activeBranchId: input.activeBranchId } : {}),
    ...(input.selectedBranchId ? { selectedBranchId: input.selectedBranchId } : {}),
    branches: input.branches,
  };
}

export function timelineBranchSummary(
  id: string,
  active: boolean,
  entries: readonly SessionTimelineEntry[],
): TimelineBranchSummary {
  const projection = projectTimeline(entries);
  const name = branchName(entries);
  return {
    id,
    active,
    itemCount: projection.items.length,
    messageCount: projection.messageCount,
    activityCount: projection.activityCount,
    turnCount: projection.turnCount,
    ...(name ? { name } : {}),
    ...(entryTimestamp(entries.at(-1)?.record) ? { updatedAt: entryTimestamp(entries.at(-1)?.record)! } : {}),
  };
}

function projectActivity(record: Record<string, unknown>): TimelineActivity {
  const type = boundedString(record.type, 100) || "unknown";
  const at = entryTimestamp(record);
  if (type === "custom") {
    return projectCustomActivity(record, at);
  }
  if (type === "model_change") {
    const model = boundedString(record.modelId, 240);
    return activity({
      category: "configuration",
      status: "recorded",
      title: "model_change",
      detail: model,
      at,
    });
  }
  if (type === "thinking_level_change") {
    return activity({
      category: "configuration",
      status: "recorded",
      title: "thinking_level_change",
      detail: boundedString(record.thinkingLevel, 100),
      at,
    });
  }
  if (type === "session_info") {
    return activity({
      category: "configuration",
      status: "recorded",
      title: "session_info",
      detail: boundedString(record.name, 500),
      at,
    });
  }
  return activity({
    category: type.includes("compact") ? "context" : "system",
    status: "recorded",
    title: type,
    at,
  });
}

function projectCustomActivity(
  record: Record<string, unknown>,
  at: string | undefined,
): TimelineActivity {
  const customType = boundedString(record.customType, 160) || "custom";
  const data = asObject(record.data);
  if (customType === "ts-workspace-subagent-run") {
    return activity({
      category: "subagent",
      status: data.schema_valid === false ? "failed" : "completed",
      title: "subagent_run",
      role: boundedString(data.role, 100),
      operation: boundedString(data.operation, 160),
      nodeRefs: boundedStrings(data.node_refs),
      durationMs: nonNegativeInteger(data.duration_ms),
      totalTokens: nonNegativeInteger(asObject(data.usage).total),
      reference: boundedReference(data.run_ref),
      at,
    });
  }
  if (customType === "ts-workspace-subagent-failed") {
    return activity({
      category: "subagent",
      status: "failed",
      title: "subagent_failed",
      role: boundedString(data.role, 100),
      operation: boundedString(data.operation, 160),
      nodeRefs: boundedStrings(data.node_refs),
      detail: boundedString(data.failure_class, 160),
      stage: boundedString(data.failure_stage, 160),
      retrySafe: typeof data.retry_safe === "boolean" ? data.retry_safe : undefined,
      reference: boundedReference(data.run_ref),
      at,
    });
  }
  if (customType === "ts-deterministic-activity" || customType === "ts-deterministic-activity-failed") {
    const failed = customType.endsWith("-failed");
    return activity({
      category: "research",
      status: failed ? "failed" : "completed",
      title: failed ? "research_activity_failed" : "research_activity",
      operation: boundedString(data.operation, 160),
      nodeRefs: boundedStrings(data.node_id ? [data.node_id] : data.node_refs),
      detail: failed
        ? boundedString(data.error_class ?? data.kind, 160)
        : undefined,
      reference: boundedReference(data.activity_ref),
      at,
    });
  }
  if (customType === "ts-review-root-disposition") {
    return activity({
      category: "review",
      status: "completed",
      title: "review_disposition",
      detail: boundedString(data.disposition, 160),
      reference: boundedReference(data.review_run_ref),
      at,
    });
  }
  if (customType === "ts-workspace-validation-result") {
    return activity({
      category: "workspace",
      status: "recorded",
      title: "workspace_validation",
      at,
    });
  }
  if (customType === "ts-workspace-context-result") {
    return activity({
      category: "context",
      status: "recorded",
      title: "workspace_context",
      at,
    });
  }
  return activity({
    category: "system",
    status: "recorded",
    title: customType,
    at,
  });
}

function activity(value: TimelineActivityDraft): TimelineActivity {
  return Object.fromEntries(
    Object.entries(value).filter(([, candidate]) => candidate !== undefined && candidate !== ""),
  ) as unknown as TimelineActivity;
}

function messageRole(message: unknown): string | undefined {
  return asObject(message).role as string | undefined;
}

function branchName(entries: readonly SessionTimelineEntry[]): string | undefined {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const record = entries[index]!.record;
    if (record.type === "session_info") {
      const name = boundedString(record.name, 500);
      if (name) return name;
    }
  }
  return undefined;
}

function entryTimestamp(record: Record<string, unknown> | undefined): string | undefined {
  if (!record) return undefined;
  const value = record.timestamp;
  if (typeof value === "string" && Number.isFinite(Date.parse(value))) return new Date(value).toISOString();
  if (typeof value === "number" && Number.isFinite(value)) {
    const parsed = new Date(value);
    if (Number.isFinite(parsed.getTime())) return parsed.toISOString();
  }
  return undefined;
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function boundedString(value: unknown, maximum: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  if (!normalized) return undefined;
  return normalized.length <= maximum ? normalized : `${normalized.slice(0, maximum)}...`;
}

function boundedStrings(value: unknown): string[] | undefined {
  const values = Array.isArray(value) ? value : [];
  const result = values
    .flatMap((candidate) => {
      const parsed = boundedString(candidate, 160);
      return parsed ? [parsed] : [];
    })
    .slice(0, MAX_ACTIVITY_REFS);
  return result.length ? result : undefined;
}

function boundedReference(value: unknown): string | undefined {
  const reference = boundedString(value, 500);
  if (!reference
    || reference.startsWith("/")
    || reference.includes("\\")
    || reference.split("/").includes("..")
    || !/^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(reference)) {
    return undefined;
  }
  return reference;
}

function nonNegativeInteger(value: unknown): number | undefined {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : undefined;
}
