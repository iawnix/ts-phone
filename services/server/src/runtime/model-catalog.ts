import { HttpError } from "../errors.js";
import type { PhoneModel } from "../types.js";

export function parseModelCatalog(value: unknown): PhoneModel[] {
  if (!value || typeof value !== "object" || !("models" in value) || !Array.isArray(value.models)
    || !("schemaVersion" in value) || value.schemaVersion !== "ts-phone-models/1" || value.models.length > 2_000) {
    throw new HttpError(502, "model_check_failed", "Host model catalog is invalid");
  }
  return value.models.map((model: unknown) => {
    if (!model || typeof model !== "object") throw new HttpError(502, "model_check_failed", "Host model is invalid");
    const row = model as Record<string, unknown>;
    for (const [field, limit] of [["provider", 160], ["id", 240], ["name", 240]] as const) {
      if (typeof row[field] !== "string" || !row[field] || (row[field] as string).length > limit
        || /[\u0000-\u001f]/.test(row[field] as string)) {
        throw new HttpError(502, "model_check_failed", "Host model is invalid");
      }
    }
    if (!Number.isSafeInteger(row.contextWindow) || (row.contextWindow as number) <= 0) {
      throw new HttpError(502, "model_check_failed", "Host model context limit is invalid");
    }
    // Never forward provider URLs, authentication, headers, or raw config.
    return { provider: row.provider as string, id: row.id as string, name: row.name as string,
      contextWindow: row.contextWindow as number };
  }).sort((a, b) => a.provider.localeCompare(b.provider) || a.name.localeCompare(b.name));
}
