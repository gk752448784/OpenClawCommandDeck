import { describe, expect, it } from "vitest";

import { buildAlertsDashboardModel } from "@/lib/selectors/alerts-dashboard";
import type { AlertModel } from "@/lib/types/view-models";

const alerts: AlertModel[] = [
  {
    id: "cron-2",
    sourceId: "memory-cleaner",
    targetId: "job-2",
    severity: "high",
    category: "Cron",
    title: "记忆清洁提醒执行失败",
    summary: "Delivering to Feishu requires target",
    recommendedAction: "补充 `delivery.to`",
    needsRepair: true
  },
  {
    id: "cron-1",
    sourceId: "review",
    targetId: "job-1",
    severity: "medium",
    category: "Cron",
    title: "每日复盘延迟",
    summary: "最近一次执行失败",
    recommendedAction: "查看任务详情",
    needsRepair: false
  }
];

describe("alerts dashboard selector", () => {
  it("sorts urgent alerts first and summarizes disposal state", () => {
    const model = buildAlertsDashboardModel(alerts);

    expect(model.summary.total).toBe(2);
    expect(model.summary.high).toBe(1);
    expect(model.summary.medium).toBe(1);
    expect(model.items[0]?.title).toContain("记忆清洁");
    expect(model.items[0]?.needsRepair).toBe(true);
    expect(model.items[0]?.primaryAction).toBe("立即修复");
    expect(model.items[1]?.primaryAction).toBe("查看建议");
  });
});
