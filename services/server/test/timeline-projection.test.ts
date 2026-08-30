import assert from "node:assert/strict";
import test from "node:test";
import { projectTimeline } from "../src/timeline-projection.js";

test("timeline activities expose allowlisted summaries without raw provider or failure text", () => {
  const projection = projectTimeline([{
    id: "00000001",
    parentId: null,
    record: {
      type: "model_change",
      provider: "private-provider",
      modelId: "review-model",
    },
  }, {
    id: "00000002",
    parentId: "00000001",
    record: {
      type: "custom",
      customType: "ts-deterministic-activity-failed",
      data: {
        operation: "gaussian_submit",
        error_class: "RemoteCommandError",
        message: "credential-shaped private failure text",
        activity_ref: "/home/private/activity.json",
      },
    },
  }]);

  const serialized = JSON.stringify(projection);
  assert.match(serialized, /review-model/);
  assert.match(serialized, /RemoteCommandError/);
  assert.doesNotMatch(serialized, /private-provider|credential-shaped|\/home\/private/);
});
