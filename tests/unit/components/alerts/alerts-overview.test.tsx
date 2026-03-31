import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.stubGlobal("React", React);

vi.mock("@/components/control/fix-cron-target-form", () => ({
  FixCronTargetForm: () => <div data-testid="fix-cron-target-form" />
}));

const alerts = [
  {
    id: "alert-1",
    sourceId: "memory-cleaner",
    targetId: "job-1",
    severity: "high",
    category: "Cron",
    title: "记忆清洁提醒执行失败",
    summary: "Delivering to Feishu requires target",
    recommendedAction: "补充 `delivery.to`",
    needsRepair: true
  },
  {
    id: "alert-2",
    sourceId: "daily-review",
    targetId: "job-2",
    severity: "medium",
    category: "Cron",
    title: "每日复盘延迟",
    summary: "最近一次执行偏晚，但尚未中断流程",
    recommendedAction: "观察下一轮执行",
    needsRepair: false
  }
] as const;

describe("AlertsOverview", () => {
  it("renders a triage-first layout", async () => {
    const { AlertsOverview } = await import("@/components/alerts/alerts-overview");
    const markup = renderToStaticMarkup(<AlertsOverview alerts={[...alerts]} />);

    expect(markup).toContain("alerts-overview");
    expect(markup).toContain("待处理异常");
    expect(markup).toContain("优先处理");
    expect(markup).toContain("记忆清洁提醒执行失败");
    expect(markup).toContain("每日复盘延迟");
    expect(markup).not.toContain("management-card-");
    expect(markup).toContain("alerts-overview-form-embed");
  });
});
