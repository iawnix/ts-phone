import { HttpError } from "../errors.js";
import { promptFailure } from "./worker-rpc.js";

export function readLauncherError(diagnostic: unknown): HttpError | undefined {
  if (typeof diagnostic !== "string") return undefined;
  // Only fixed launcher codes cross the public boundary, never raw stderr.
  for (const line of diagnostic.split("\n")) {
    let record: unknown;
    try { record = JSON.parse(line); } catch { continue; }
    if (!record || typeof record !== "object" || Array.isArray(record)) continue;
    const value = record as Record<string, unknown>;
    if (value.type !== "tspi.startup_error" || Object.keys(value).length !== 2) continue;
    switch (value.code) {
      case "session_writer_active":
        return new HttpError(409, value.code, "An existing workspace or conversation writer holds the required guard");
      case "session_guard_upgrade_required":
        return new HttpError(409, value.code, "Complete the TSPi Package guard upgrade before activating conversations");
      case "session_writer_inspection_failed":
        return new HttpError(503, value.code, "The Host could not complete its session guard check; inspect the TSPi installation diagnostics");
      case "session_guard_invalid":
        return new HttpError(409, value.code, "The Host could not validate the conversation history or its writer guards");
      case "model_unavailable":
      case "model_check_failed":
        return promptFailure(value.code);
    }
  }
  return undefined;
}
