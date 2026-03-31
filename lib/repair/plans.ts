import type { RepairPlan, RootCauseAssessment } from "@/lib/types/issues";

export function buildRepairPlanForRootCause(rootCause: RootCauseAssessment): RepairPlan {
  switch (rootCause.type) {
    case "channel_disabled":
      return {
        repairability: "auto",
        summary: `重新启用 ${rootCause.impactScope} 渠道`,
        steps: [
          `启用 ${rootCause.impactScope} 渠道开关。`,
          "重新加载配置并验证渠道状态。"
        ],
        actions: [
          {
            kind: "enable_channel",
            label: `启用 ${rootCause.impactScope} 渠道`
          }
        ],
        fallbackManualSteps: [
          `使用 openclaw config set channels.${rootCause.impactScope}.enabled true --strict-json`
        ]
      };
    case "plugin_disabled":
      return {
        repairability: "auto",
        summary: `重新启用 ${rootCause.impactScope} 对应插件`,
        steps: [
          "启用目标插件。",
          "重新检查渠道与插件状态是否一致。"
        ],
        actions: [
          {
            kind: "enable_plugin",
            label: `启用 ${rootCause.impactScope} 插件`
          }
        ],
        fallbackManualSteps: [
          "通过 openclaw config set plugins.entries.<plugin>.enabled true --strict-json 手动修复。"
        ]
      };
    case "primary_model_missing":
    case "primary_model_unavailable":
      return {
        repairability: "confirm",
        summary: `切换主模型以修复 ${rootCause.impactScope} 问题`,
        steps: [
          "选择一个可用候选模型。",
          "确认切换主模型。",
          "重新验证主模型配置。"
        ],
        actions: [
          {
            kind: "switch_model",
            label: "切换主模型"
          }
        ],
        fallbackManualSteps: [
          "手动修改 agents.defaults.model.primary 并重新验证候选模型列表。"
        ]
      };
    case "gateway_unreachable":
    case "gateway_restart_required":
      return {
        repairability: "confirm",
        summary: "重启 gateway 并验证连通性",
        steps: [
          "执行 gateway restart。",
          "等待 gateway 恢复。",
          "重新执行 reachability 检查。"
        ],
        actions: [
          {
            kind: "restart_gateway",
            label: "重启 Gateway"
          }
        ],
        fallbackManualSteps: [
          "手动执行 openclaw gateway restart 后重新访问状态接口。"
        ]
      };
    case "channel_plugin_mismatch":
      return {
        repairability: "confirm",
        summary: `对齐 ${rootCause.impactScope} 的渠道与插件状态`,
        steps: [
          "检查渠道开关与插件开关。",
          "按目标状态对齐配置。",
          "重新验证状态一致性。"
        ],
        actions: [
          {
            kind: "enable_plugin",
            label: "对齐插件状态"
          }
        ],
        fallbackManualSteps: [
          "手动检查 channels.* 和 plugins.entries.* 的 enabled 配置。"
        ]
      };
    default:
      return {
        repairability: "manual",
        summary: `需要人工处理 ${rootCause.type}`,
        steps: ["查看根因证据并按说明人工修复。"],
        actions: [],
        fallbackManualSteps: [rootCause.details]
      };
  }
}
