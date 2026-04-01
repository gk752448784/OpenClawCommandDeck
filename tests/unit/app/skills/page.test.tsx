import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

let mockedDashboardData: any;
const loadSkillsDashboardData = vi.fn();

vi.stubGlobal("React", React);

vi.mock("next/navigation", () => ({
  usePathname: () => "/skills",
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

vi.mock("@/lib/server/skills", () => ({
  loadSkillsDashboardData
}));

describe("SkillsPage", () => {
  it("renders the shell immediately and leaves skill loading to the client panel", async () => {
    mockedDashboardData = {
      overview: {
        topBar: {
          appName: "OpenClaw 控制中心",
          health: "warning",
          timezone: "Asia/Shanghai",
          instanceLabel: "本地运行与协作面板",
          statusSummary: "存在待补齐的能力依赖。",
          channelSummary: { online: 3, total: 4 },
          agentSummary: { active: 2, total: 3 },
          alertsToday: 2,
          primaryModel: "openai/gpt-5.4",
          quickActions: []
        }
      }
    };

    const { default: SkillsPage } = await import("@/app/skills/page");
    const markup = renderToStaticMarkup(await SkillsPage());

    expect(markup).toContain("Skills");
    expect(markup).toContain("当前技能清单与缺失依赖");
    expect(markup).toContain("技能清单加载中");
    expect(markup).toContain("页面先加载框架");
    expect(markup).toContain("skills-loading-shell");
    expect(loadSkillsDashboardData).not.toHaveBeenCalled();
  });
});
