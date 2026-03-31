import { describe, expect, it } from "vitest";

import { buildCronDashboardModel } from "@/lib/selectors/cron-dashboard";
import type { CronJobs } from "@/lib/validators/cron-jobs";

const cron: CronJobs = {
  version: 1,
  jobs: [
    {
      id: "job-1",
      agentId: "main",
      name: "daily-review",
      description: "每日复盘",
      enabled: true,
      schedule: {
        kind: "cron",
        expr: "0 4 * * *",
        tz: "Asia/Shanghai"
      },
      delivery: {
        mode: "none",
        channel: "last"
      },
      state: {
        nextRunAtMs: 1774555200000,
        lastRunStatus: "ok",
        lastStatus: "ok"
      }
    },
    {
      id: "job-2",
      agentId: "main",
      name: "memory-cleaner",
      description: "记忆清洁提醒",
      enabled: true,
      schedule: {
        kind: "cron",
        expr: "0 21 16 * *",
        tz: "Asia/Shanghai"
      },
      delivery: {
        mode: "announce",
        channel: "feishu"
      },
      state: {
        nextRunAtMs: 1776344400000,
        lastRunStatus: "error",
        lastStatus: "error",
        lastError: "Delivering to Feishu requires target <chatId|user:openId|chat:chatId>",
        consecutiveErrors: 1
      }
    }
  ]
};

describe("cron dashboard selector", () => {
  it("builds a product-friendly summary and actionable cards", () => {
    const model = buildCronDashboardModel(cron);

    expect(model.summary.total).toBe(2);
    expect(model.summary.enabled).toBe(2);
    expect(model.summary.failed).toBe(1);
    expect(model.summary.needsRepair).toBe(1);
    expect(model.items[0]?.statusTone).toBe("warning");
    expect(model.items[0]?.primaryAction).toBe("修复投递");
    expect(model.items[0]?.deliverySummary).toBe("广播 · feishu");
    expect(model.items[1]?.statusTone).toBe("healthy");
    expect(model.items[1]?.deliverySummary).toBe("未配置");
  });
});
