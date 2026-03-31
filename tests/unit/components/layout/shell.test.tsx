import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { AppShell } from "@/components/layout/app-shell";
import type { TopBarModel } from "@/lib/types/view-models";

let mockedPathname = "/workbench";

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

const topBarModel: TopBarModel = {
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
  quickActions: [
    {
      href: "/alerts",
      label: "告警中心"
    }
  ]
};

describe("AppShell", () => {
  beforeEach(() => {
    mockedPathname = "/workbench";
  });

  it("defaults secondary shells to the compact header", () => {
    const markup = renderToStaticMarkup(
      <AppShell topBar={topBarModel}>
        <div>content</div>
      </AppShell>
    );

    expect(markup).toContain('data-shell-variant="compact"');
    expect(markup).toContain('data-top-bar-variant="compact"');
    expect(markup).not.toContain('data-top-bar-variant="hero"');
    expect(markup).toContain("Command Deck");
    expect(markup).toContain("Observe");
    expect(markup).toContain("Act");
    expect(markup).toContain("OpenClaw 控制中心");
    expect(markup).toContain("系统整体稳定，当前 3 个渠道状态正常。");
  });

  it("renders the hero as a posture-led workbench header", () => {
    const markup = renderToStaticMarkup(
      <AppShell topBar={topBarModel} topBarVariant="hero">
        <div>content</div>
      </AppShell>
    );

    expect(markup).toContain("系统整体稳定，当前 3 个渠道状态正常。");
    expect(markup).toContain("Mission Control");
    expect(markup).toContain("告警需先处理");
    expect(markup).toContain("主模型");
    expect(markup).toContain("openai/gpt-5.3-codex");
    expect(markup).toContain("top-bar-actions");
    expect(markup).not.toContain("<h1>OpenClaw 控制中心</h1>");
  });

  it("hides the top bar when requested", () => {
    const markup = renderToStaticMarkup(
      <AppShell topBar={topBarModel} topBarVariant="hidden">
        <div>content</div>
      </AppShell>
    );

    expect(markup).toContain('data-shell-variant="hidden"');
    expect(markup).not.toContain('data-top-bar-variant="compact"');
    expect(markup).not.toContain('data-top-bar-variant="hero"');
    expect(markup).not.toContain("OpenClaw 控制中心");
  });

  it("keeps section links active for nested routes", () => {
    mockedPathname = "/alerts/detail/123";

    const markup = renderToStaticMarkup(
      <AppShell topBar={topBarModel}>
        <div>content</div>
      </AppShell>
    );

    expect(markup).toContain('href="/alerts" class="side-nav-link side-nav-link-active"');
    expect(markup).not.toContain('href="/control" class="side-nav-link side-nav-link-active"');
  });

  it("reframes shared navigation and exposes a compact shell variant", () => {
    const markup = renderToStaticMarkup(
      <AppShell topBar={topBarModel} topBarVariant="compact" pageTitle="运行控制" pageSubtitle="常用动作">
        <div>content</div>
      </AppShell>
    );

    expect(markup).toContain('data-shell-variant="compact"');
    expect(markup).toContain("Command Deck");
    expect(markup).toContain("Observe");
    expect(markup).toContain("Act");
    expect(markup).toContain("Operate");
    expect(markup).toContain("Configure");
    expect(markup).toContain("运行控制");
    expect(markup).toContain("常用动作");
    expect(markup).toContain("本地 AI 编排与运维");
  });
});
