import { describe, expect, it } from "vitest";

import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { loadHeartbeatGuide } from "@/lib/adapters/heartbeat";
import { loadAgentDefinitions } from "@/lib/adapters/agents";
import { buildOverviewModel } from "@/lib/selectors/overview";
import { OPENCLAW_FIXTURE_ROOT } from "@/tests/unit/helpers/openclaw-fixture";

describe("overview selector", () => {
  it("builds the command-deck overview from local data", async () => {
    const [configResult, cronResult, heartbeatResult, agentResult] = await Promise.all([
      loadOpenClawConfig(`${OPENCLAW_FIXTURE_ROOT}/openclaw.json`),
      loadCronJobs(`${OPENCLAW_FIXTURE_ROOT}/cron/jobs.json`),
      loadHeartbeatGuide(`${OPENCLAW_FIXTURE_ROOT}/workspace/HEARTBEAT.md`),
      loadAgentDefinitions(OPENCLAW_FIXTURE_ROOT)
    ]);

    expect(configResult.ok).toBe(true);
    expect(cronResult.ok).toBe(true);
    expect(heartbeatResult.ok).toBe(true);
    expect(agentResult.ok).toBe(true);

    if (!configResult.ok || !cronResult.ok || !heartbeatResult.ok || !agentResult.ok) {
      throw new Error("expected all source data to load");
    }

    const overview = buildOverviewModel({
      config: configResult.data,
      cron: cronResult.data,
      heartbeat: heartbeatResult.data,
      agents: agentResult.data
    });

    expect(overview.topBar.appName).toBe("OpenClaw 控制中心");
    expect(overview.topBar.instanceLabel).toBe("本地运行与协作面板");
    expect(overview.topBar.statusSummary).toContain("整体");
    expect(overview.topBar.channelSummary.online).toBeGreaterThanOrEqual(2);
    expect(overview.priorityCards.length).toBeGreaterThan(0);
    expect(overview.priorityCards.some((card) => card.type === "计划任务失败")).toBe(
      true
    );
    expect(overview.roleCards).toHaveLength(3);
    expect(overview.rightRail.cron.failedCount).toBeGreaterThanOrEqual(1);
    expect(overview.topBar.quickActions?.some((item) => item.label === "告警中心")).toBe(
      true
    );
    expect(overview.topBar.quickActions?.some((item) => item.label === "运行控制")).toBe(
      true
    );
    expect(overview.todayTimeline.some((item) => item.label.includes("daily-self-reflection"))).toBe(
      true
    );
  });
});
