import { describe, expect, it } from "vitest";

import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { buildAlertsModel } from "@/lib/selectors/alerts";
import { OPENCLAW_FIXTURE_ROOT } from "@/tests/unit/helpers/openclaw-fixture";

describe("alerts selector", () => {
  it("extracts actionable alerts from failed local jobs", async () => {
    const cronResult = await loadCronJobs(`${OPENCLAW_FIXTURE_ROOT}/cron/jobs.json`);

    expect(cronResult.ok).toBe(true);
    if (!cronResult.ok) {
      throw new Error("expected cron jobs to load");
    }

    const alerts = buildAlertsModel({
      cron: cronResult.data
    });

    const memoryCleanerFailure = alerts.find(
      (alert) => alert.sourceId === "monthly-memory-cleaner-reminder"
    );

    expect(memoryCleanerFailure).toBeDefined();
    expect(memoryCleanerFailure?.targetId).toBe("62b3510c-029c-423b-a9d1-9bc9a608627f");
    expect(memoryCleanerFailure?.severity).toBe("high");
    expect(memoryCleanerFailure?.title).toContain("记忆清洁");
    expect(memoryCleanerFailure?.recommendedAction).toContain("delivery.to");
    expect(memoryCleanerFailure?.category).toBe("Cron");
  });
});
