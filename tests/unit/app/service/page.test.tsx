import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

let mockedDashboardData: any;

vi.stubGlobal("React", React);

vi.mock("next/navigation", () => ({
  usePathname: () => "/service",
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

describe("ServicePage", () => {
  it("renders service management controls and gateway status", async () => {
    mockedDashboardData = {
      overview: {
        topBar: {
          appName: "OpenClaw 控制中心",
          health: "healthy",
          timezone: "Asia/Shanghai",
          statusSummary: "系统稳定",
          channelSummary: { online: 3, total: 4 },
          agentSummary: { active: 2, total: 3 },
          alertsToday: 0,
          primaryModel: "openai/gpt-5.4",
          quickActions: []
        }
      }
    };
    const { default: ServicePage } = await import("@/app/service/page");
    const markup = renderToStaticMarkup(await ServicePage());

    expect(markup).toContain("服务管理");
    expect(markup).toContain("Gateway 状态");
    expect(markup).toContain("加载服务状态中");
    expect(markup).toContain('data-action="gateway-restart"');
    expect(markup).toContain('data-action="gateway-start"');
    expect(markup).toContain('data-action="gateway-stop"');
    expect(markup).toContain("配置备份与恢复");
    expect(markup).toContain("加载备份列表中");
  });
});
