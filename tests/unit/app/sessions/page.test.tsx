import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

let mockedDashboardData: any;
let mockedIssueSignals: any;
let mockedIssues: any;
let mockedSessionsSnapshot: any;

vi.stubGlobal("React", React);

vi.mock("next/navigation", () => ({
  usePathname: () => "/sessions",
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
  loadCoreDashboardData: vi.fn(async () => mockedDashboardData),
  loadIssueSignals: vi.fn(async () => mockedIssueSignals)
}));

vi.mock("@/lib/adapters/sessions", () => ({
  loadSessionsSnapshot: vi.fn(async () => ({
    ok: true,
    data: mockedSessionsSnapshot
  }))
}));

vi.mock("@/lib/issues/build-issues", () => ({
  buildIssues: vi.fn(() => mockedIssues)
}));

function buildDashboardData() {
  return {
    overview: {
      topBar: {
        appName: "OpenClaw 控制中心",
        health: "warning",
        timezone: "Asia/Shanghai",
        instanceLabel: "本地运行与协作面板",
        statusSummary: "系统存在需要排查的会话异常。",
        channelSummary: {
          online: 3,
          total: 4
        },
        agentSummary: {
          active: 2,
          total: 3
        },
        alertsToday: 1,
        primaryModel: "openai/gpt-5.4",
        quickActions: []
      }
    },
    agents: [{ id: "writer" }]
  };
}

describe("SessionsPage", () => {
  it("renders session issue counts and log repair clues", async () => {
    mockedDashboardData = buildDashboardData();
    mockedIssueSignals = {
      channels: [],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.4"]
      },
      gateway: {
        reachable: "reachable"
      },
      logs: {
        excerpts: ["dispatch failed session=writer-main agent=writer timeout"],
        tokens: ["dispatch", "failed", "writer"],
        references: [
          {
            lineIndex: 0,
            agentId: "writer",
            sessionKey: "session:writer:discord:writer-main"
          }
        ],
        relatedSessionKeys: ["session:writer:discord:writer-main"],
        relatedAgentIds: ["writer"]
      }
    };
    mockedIssues = [
      {
        id: "agent:session_log_error_detected:session:writer:discord:writer-main",
        source: "Agent",
        title: "Writer 会话日志出现错误",
        summary: "最近一条日志包含 dispatch failure。",
        severity: "high",
        rootCause: {
          type: "session_log_error_detected",
          evidence: {
            summary: "dispatch failed session=writer-main",
            detail: "retry exhausted",
            impactScope: "session:writer:discord:writer-main"
          }
        },
        repairPlan: {
          repairability: "manual",
          summary: "先排查调度失败原因，再决定是否重试。",
          steps: ["查看最近调度日志"],
          actions: [],
          fallbackManualSteps: ["手动检查代理和会话状态"]
        },
        verificationStatus: "unresolved"
      }
    ];
    mockedSessionsSnapshot = {
      count: 1,
      sessions: [
        {
          sessionId: "sess-1",
          key: "session:writer:discord:writer-main",
          updatedAt: Date.now(),
          ageMs: 60_000,
          model: "openai/gpt-5.4",
          kind: "chat",
          percentUsed: 35,
          agentId: "writer"
        }
      ]
    };

    const { default: SessionsPage } = await import("@/app/sessions/page");
    const markup = renderToStaticMarkup(await SessionsPage());

    expect(markup).toContain("会话监控");
    expect(markup).toContain("异常线索");
    expect(markup).toContain("1 条");
    expect(markup).toContain("日志与修复线索");
    expect(markup).toContain("dispatch failed session=writer-main agent=writer timeout");
  });
});
