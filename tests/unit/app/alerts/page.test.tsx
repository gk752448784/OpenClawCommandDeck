import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

let mockedDashboardData: any;

vi.stubGlobal("React", React);

vi.mock("next/navigation", () => ({
  usePathname: () => "/alerts",
  useRouter: () => ({
    refresh: vi.fn(),
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
    back: vi.fn(),
    forward: vi.fn()
  })
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

function buildDashboardData() {
  return {
    overview: {
      topBar: {
        appName: "OpenClaw 控制中心",
        health: "warning",
        timezone: "Asia/Shanghai",
        instanceLabel: "本地运行与协作面板",
        statusSummary: "系统出现 2 个需要处理的异常。",
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
        quickActions: [
          {
            href: "/control",
            label: "运行控制"
          }
        ]
      }
    },
    alerts: [
      {
        id: "alert-1",
        sourceId: "memory-cleaner",
        targetId: "job-1",
        severity: "high",
        category: "Cron",
        title: "记忆清洁提醒执行失败",
        summary: "Delivering to Feishu requires target",
        recommendedAction: "补充 `delivery.to`"
      },
      {
        id: "alert-2",
        sourceId: "daily-review",
        targetId: "job-2",
        severity: "medium",
        category: "Cron",
        title: "每日复盘延迟",
        summary: "最近一次执行偏晚，但尚未中断流程",
        recommendedAction: "观察下一轮执行"
      }
    ],
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

describe("AlertsPage", () => {
  it("uses the compact mission-control framing", async () => {
    mockedDashboardData = buildDashboardData();
    const { default: AlertsPage } = await import("@/app/alerts/page");
    const markup = renderToStaticMarkup(await AlertsPage());

    expect(markup).toContain('data-shell-variant="compact"');
    expect(markup).toContain('data-top-bar-variant="compact"');
    expect(markup).toContain("告警分诊");
    expect(markup).toContain("只看需要动作的异常");
    expect(markup.indexOf("待处理异常")).toBeLessThan(markup.indexOf("Triage first"));
  });
});
