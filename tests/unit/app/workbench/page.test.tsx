import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

let mockedPathname = "/workbench";
let mockedDashboardData: any;

vi.stubGlobal("React", React);

vi.mock("next/navigation", () => ({
  usePathname: () => mockedPathname
}));

vi.mock("next/link", () => ({
  default: ({
    href,
    className,
    children
  }: {
    href: string;
    className?: string;
    children: React.ReactNode;
  }) => (
    <a href={href} className={className}>
      {children}
    </a>
  )
}));

vi.mock("@/lib/server/load-dashboard-data", () => ({
  loadCoreDashboardData: vi.fn(async () => mockedDashboardData)
}));

function buildDashboardData({
  health = "healthy",
  quickActions = [
    {
      href: "/alerts",
      label: "告警中心"
    },
    {
      href: "/control",
      label: "运行控制"
    },
    {
      href: "/channels",
      label: "消息渠道"
    }
  ]
}: {
  health?: "healthy" | "warning" | "critical";
  quickActions?: Array<{
    href: string;
    label: string;
  }>;
} = {}) {
  return {
    overview: {
      topBar: {
        appName: "OpenClaw 控制中心",
        health,
        timezone: "Asia/Shanghai",
        instanceLabel: "本地运行与协作面板",
        statusSummary: "系统整体稳定，当前 3 个渠道状态正常。",
        channelSummary: {
          online: 3,
          total: 4
        },
        agentSummary: {
          active: 2,
          total: 3
        },
        alertsToday: 2,
        primaryModel: "openai/gpt-5.3-codex",
        quickActions
      },
      priorityCards: [
        {
          id: "priority-1",
          title: "记忆清洁提醒执行失败",
          type: "计划任务失败",
          source: "cron",
          summary: "Delivering to Feishu requires target",
          recommendedAction: "补充 `delivery.to`",
          severity: "high"
        },
        {
          id: "priority-2",
          title: "每日复盘延迟",
          type: "计划任务提醒",
          source: "cron",
          summary: "最近一次执行偏晚，但尚未中断流程",
          recommendedAction: "观察下一轮执行",
          severity: "medium"
        }
      ],
      todayTimeline: [
        {
          id: "timeline-1",
          label: "daily-self-reflection",
          schedule: "08:00",
          type: "cron"
        }
      ],
      suggestions: [
        {
          id: "suggestion-1",
          source: "chief-of-staff",
          title: "先修复失败的计划任务",
          summary: "存在需要人工处理的失败任务，优先补齐投递目标再恢复节奏。"
        }
      ],
      roleCards: [],
      rightRail: {
        channels: {
          healthyCount: 3,
          totalCount: 4
        },
        agents: {
          activeCount: 2,
          totalCount: 3
        },
        cron: {
          total: 4,
          failedCount: 1
        },
        heartbeat: {
          enabled: true,
          notes: ["- HEARTBEAT_OK"]
        }
      }
    },
    alerts: [],
    channels: {
      online: 3,
      total: 4
    },
    cronSummary: {
      total: 4,
      failedCount: 1
    },
    agentsSummary: {
      activeCount: 2,
      totalCount: 3
    },
    agents: [],
    config: {},
    cron: []
  };
}

describe("WorkbenchPage", () => {
  it("renders the mission-control homepage composition", async () => {
    mockedDashboardData = buildDashboardData();
    const { default: WorkbenchPage } = await import("@/app/workbench/page");
    const markup = renderToStaticMarkup(await WorkbenchPage());

    expect(markup).toContain("系统整体稳定，当前 3 个渠道状态正常。");
    expect(markup).toContain("优先队列");
    expect(markup).toContain("系统脉冲");
    expect(markup).toContain("快速动作");
    expect(markup).toContain("行动建议");
    expect(markup).toContain("今日节奏");
    expect(markup).toContain("主动建议");
    expect(markup).toContain("主模型");
    expect(markup).toContain("openai/gpt-5.3-codex");
    expect(markup).toContain("记忆清洁提醒执行失败");
    expect(markup).toContain("每日复盘延迟");
    expect(markup).toContain("priority-medium");
    expect(markup).toContain("推荐动作");
    expect(markup).toContain("告警中心");
    expect(markup).toContain("运行控制");
    expect(markup).toContain("消息渠道");
    expect(markup).toContain("quick-action-card");
    expect((markup.match(/quick-action-card/g) ?? []).length).toBe(3);
    expect(markup).toContain("mission-control-posture");
    expect(markup).toContain("system-pulse-strip");
  });

  it("keeps warning and critical runtime posture distinct", async () => {
    const { default: WorkbenchPage } = await import("@/app/workbench/page");

    mockedDashboardData = buildDashboardData({ health: "warning" });
    const warningMarkup = renderToStaticMarkup(await WorkbenchPage());

    mockedDashboardData = buildDashboardData({ health: "critical" });
    const criticalMarkup = renderToStaticMarkup(await WorkbenchPage());

    expect(warningMarkup).toContain("运行姿态");
    expect(warningMarkup).toContain("Warning");
    expect(criticalMarkup).toContain("Critical");
    expect(warningMarkup).not.toBe(criticalMarkup);
  });

  it("omits the quick-actions section when there are no actions", async () => {
    mockedDashboardData = buildDashboardData({ quickActions: [] });
    const { default: WorkbenchPage } = await import("@/app/workbench/page");
    const markup = renderToStaticMarkup(await WorkbenchPage());

    expect(markup).not.toContain("top-bar-actions");
    expect(markup).not.toContain("快速动作");
    expect(markup).not.toContain("quick-action-card");
  });
});
