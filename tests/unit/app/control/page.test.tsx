import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

let mockedDashboardData: any;
let mockedConfigResult: any;
let mockedCronResult: any;

vi.stubGlobal("React", React);

vi.mock("next/navigation", () => ({
  usePathname: () => "/control",
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

vi.mock("@/components/control/action-button", () => ({
  ActionButton: ({
    action,
    payload,
    label
  }: {
    action: string;
    payload: Record<string, unknown>;
    label: string;
  }) => (
    <button data-action={action} data-payload={JSON.stringify(payload)}>
      {label}
    </button>
  )
}));

vi.mock("@/lib/server/load-dashboard-data", () => ({
  loadCoreDashboardData: vi.fn(async () => mockedDashboardData)
}));

vi.mock("@/lib/adapters/openclaw-config", () => ({
  loadOpenClawConfig: vi.fn(async () => mockedConfigResult)
}));

vi.mock("@/lib/adapters/cron-jobs", () => ({
  loadCronJobs: vi.fn(async () => mockedCronResult)
}));

function buildDashboardData() {
  return {
    overview: {
      topBar: {
        appName: "OpenClaw 控制中心",
        health: "healthy",
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
        alertsToday: 1,
        primaryModel: "openai/gpt-5.3-codex",
        quickActions: []
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
    agents: [
      {
        id: "agent-1",
        role: "chief-of-staff"
      }
    ],
    config: {},
    cron: []
  };
}

function buildConfigResult() {
  return {
    ok: true,
    data: {
      agents: {
        defaults: {
          model: {
            primary: "openai/gpt-5.3-codex"
          },
          models: {
            "openai/gpt-5.3-codex": {},
            "openai/gpt-5.1-codex": {}
          }
        }
      }
    }
  };
}

function buildCronResult() {
  return {
    ok: true,
    data: {
      jobs: [
        {
          id: "job-daily-review",
          name: "daily-review",
          description: "每日复盘",
          enabled: true,
          schedule: {
            expr: "0 8 * * *"
          },
          state: {}
        }
      ]
    }
  };
}

describe("ControlPage", () => {
  it("uses the compact action-zone framing", async () => {
    mockedDashboardData = buildDashboardData();
    mockedConfigResult = buildConfigResult();
    mockedCronResult = buildCronResult();

    const { default: ControlPage } = await import("@/app/control/page");
    const markup = renderToStaticMarkup(await ControlPage());

    expect(markup).toContain('data-shell-variant="compact"');
    expect(markup).toContain('data-top-bar-variant="compact"');
    expect(markup).toContain("行动区");
    expect(markup).toContain("高频动作与最近留痕");
    expect(markup).toContain("control-zone-primary");
    expect(markup).toContain("control-zone-secondary");
    expect(markup).toContain("job-daily-review");
    expect(markup).not.toContain("500475b1-3999-4853-82ea-ecf3a39483b1");
  });
});
