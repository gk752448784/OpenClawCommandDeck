import { describe, expect, it } from "vitest";

import { buildIssuesDashboardModel } from "@/lib/selectors/issues-dashboard";
import type { Issue } from "@/lib/types/issues";

const issues: Issue[] = [
  {
    id: "config:gateway_unreachable:gateway",
    source: "Config",
    title: "Gateway 当前不可达",
    summary: "模型侧诊断无法连接 gateway。",
    severity: "medium",
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
  },
  {
    id: "channel:plugin_disabled:discord",
    source: "Channel",
    title: "Discord 插件已关闭",
    summary: "消息通道存在但插件当前未启用。",
    severity: "high",
    rootCause: {
      type: "plugin_disabled",
      evidence: {
        summary: "discord plugin disabled",
        detail: "plugins.entries.discord.enabled=false",
        impactScope: "discord"
      }
    },
    repairPlan: {
      repairability: "auto",
      summary: "直接启用 discord 插件。",
      steps: ["启用 discord 插件", "重新验证渠道状态"],
      actions: [{ kind: "enable_plugin", label: "启用插件" }],
      fallbackManualSteps: ["手动修改配置并重试"]
    },
    verificationStatus: "unresolved"
  }
];

describe("issues dashboard selector", () => {
  it("sorts urgent auto-repairable issues first and summarizes triage state", () => {
    const model = buildIssuesDashboardModel(issues);

    expect(model.summary).toEqual({
      total: 2,
      high: 1,
      medium: 1,
      autoRepairable: 1
    });
    expect(model.items[0]?.id).toBe("channel:plugin_disabled:discord");
    expect(model.items[0]?.primaryAction).toBe("立即修复");
    expect(model.items[0]?.repairabilityLabel).toBe("可自动修复");
    expect(model.items[1]?.verificationLabel).toBe("部分恢复");
  });
});
