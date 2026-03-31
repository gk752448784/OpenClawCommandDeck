import { describe, expect, it } from "vitest";

import {
  loadOpenClawConfig,
  redactConfigForDashboard
} from "@/lib/adapters/openclaw-config";
import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { loadHeartbeatGuide } from "@/lib/adapters/heartbeat";
import { loadAgentDefinitions } from "@/lib/adapters/agents";
import { OPENCLAW_FIXTURE_ROOT } from "@/tests/unit/helpers/openclaw-fixture";

describe("local OpenClaw adapters", () => {
  it("loads and redacts the main config", async () => {
    const result = await loadOpenClawConfig(`${OPENCLAW_FIXTURE_ROOT}/openclaw.json`);

    expect(result.ok).toBe(true);
    if (!result.ok) {
      throw new Error("expected config to load");
    }

    const redacted = redactConfigForDashboard(result.data);

    expect(redacted.gateway.auth.token).toBe("[redacted]");
    expect(redacted.channels.feishu?.appSecret).toBe("[redacted]");
    expect(redacted.models.providers.openai.apiKey).toBe("[redacted]");
  });

  it("loads cron jobs and preserves failed job diagnostics", async () => {
    const result = await loadCronJobs(`${OPENCLAW_FIXTURE_ROOT}/cron/jobs.json`);

    expect(result.ok).toBe(true);
    if (!result.ok) {
      throw new Error("expected cron jobs to load");
    }

    const failedJob = result.data.jobs.find(
      (job) => job.name === "monthly-memory-cleaner-reminder"
    );

    expect(failedJob).toBeDefined();
    expect(failedJob?.state.lastStatus).toBe("error");
    expect(failedJob?.state.lastError).toContain("requires target");
  });

  it("loads heartbeat guidance as plain text", async () => {
    const result = await loadHeartbeatGuide(`${OPENCLAW_FIXTURE_ROOT}/workspace/HEARTBEAT.md`);

    expect(result.ok).toBe(true);
    if (!result.ok) {
      throw new Error("expected heartbeat guide to load");
    }

    expect(result.data).toContain("HEARTBEAT_OK");
    expect(result.data).toContain("每日量化汇报");
  });

  it("loads agent definitions from known workspaces", async () => {
    const result = await loadAgentDefinitions(OPENCLAW_FIXTURE_ROOT);

    expect(result.ok).toBe(true);
    if (!result.ok) {
      throw new Error("expected agent definitions to load");
    }

    expect(result.data.map((agent) => agent.id)).toEqual([
      "main",
      "chief-of-staff",
      "second-brain"
    ]);
    expect(result.data.find((agent) => agent.id === "chief-of-staff")?.role).toBe(
      "chief-of-staff"
    );
    expect(result.data.find((agent) => agent.id === "second-brain")?.role).toBe(
      "second-brain"
    );
  });

  it("returns a readable error for a missing file", async () => {
    const result = await loadCronJobs(`${OPENCLAW_FIXTURE_ROOT}/cron/missing-jobs.json`);

    expect(result.ok).toBe(false);
    if (result.ok) {
      throw new Error("expected missing file result to fail");
    }

    expect(result.error.code).toBe("missing_file");
  });
});
