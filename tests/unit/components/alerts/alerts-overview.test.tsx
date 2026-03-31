import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { Issue } from "@/lib/types/issues";

vi.stubGlobal("React", React);

vi.mock("@/components/alerts/issue-actions", () => ({
  IssueActions: () => <div data-testid="issue-actions" />
}));

const issues: Issue[] = [
  {
    id: "channel:channel_plugin_mismatch:discord",
    source: "Channel",
    severity: "high",
    title: "Discord 渠道启用但插件关闭",
    summary: "渠道状态和插件状态不一致，消息不会真正投递。",
    rootCause: {
      type: "channel_plugin_mismatch",
      evidence: {
        summary: "discord channel enabled, plugin disabled",
        detail: "plugins.entries.discord.enabled=false",
        impactScope: "discord"
      }
    },
    repairPlan: {
      repairability: "confirm",
      summary: "先确认再启用 discord 插件。",
      steps: ["检查 discord 插件开关", "启用插件并重试"],
      actions: [{ kind: "enable_plugin", label: "启用插件" }],
      fallbackManualSteps: ["手动检查 openclaw 配置"]
    },
    verificationStatus: "unresolved"
  },
  {
    id: "config:gateway_unreachable:gateway",
    source: "Config",
    severity: "medium",
    title: "Gateway 当前不可达",
    summary: "模型侧诊断无法连接 gateway。",
    rootCause: {
      type: "gateway_unreachable",
      evidence: {
        summary: "connect ECONNREFUSED",
        detail: "status command failed",
        impactScope: "gateway"
      }
    },
    repairPlan: {
      repairability: "confirm",
      summary: "确认后重启 gateway。",
      steps: ["确认当前 gateway 状态", "执行重启并重新验证"],
      actions: [{ kind: "restart_gateway", label: "重启 gateway" }],
      fallbackManualSteps: ["手动执行 openclaw gateway restart"]
    },
    verificationStatus: "partially_resolved"
  }
];

describe("AlertsOverview", () => {
  it("renders a triage-first layout", async () => {
    const { AlertsOverview } = await import("@/components/alerts/alerts-overview");
    const markup = renderToStaticMarkup(<AlertsOverview issues={[...issues]} />);

    expect(markup).toContain("alerts-overview");
    expect(markup).toContain("待处理异常");
    expect(markup).toContain("优先处理");
    expect(markup).toContain("Discord 渠道启用但插件关闭");
    expect(markup).toContain("Gateway 当前不可达");
    expect(markup).toContain("channel_plugin_mismatch");
    expect(markup).toContain("待验证");
    expect(markup).not.toContain("management-card-");
    expect(markup).toContain("data-testid=\"issue-actions\"");
  });
});
