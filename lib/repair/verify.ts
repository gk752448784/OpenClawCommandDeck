import type { ChannelSignal } from "@/lib/signals/channels";
import type { GatewaySignal } from "@/lib/signals/gateway";
import type { LogSignals } from "@/lib/signals/logs";
import type { ModelSignals } from "@/lib/signals/models";
import type { RootCauseAssessment, VerificationResult } from "@/lib/types/issues";

type VerificationSignals = {
  channels: ChannelSignal[];
  models: ModelSignals;
  gateway: GatewaySignal;
  logs: LogSignals;
};

export function verifyRootCauseResolution(
  rootCause: RootCauseAssessment,
  signals: VerificationSignals
): VerificationResult {
  switch (rootCause.type) {
    case "channel_disabled": {
      const channel = signals.channels.find((entry) => entry.channelId === rootCause.impactScope);
      return channel?.channelEnabled === true
        ? { status: "resolved", summary: `${rootCause.impactScope} 渠道已恢复启用。` }
        : { status: "unresolved", summary: `${rootCause.impactScope} 渠道仍未恢复。` };
    }

    case "plugin_disabled": {
      const channel = signals.channels.find((entry) => entry.channelId === rootCause.impactScope);
      return channel?.pluginEnabled === true
        ? { status: "resolved", summary: `${rootCause.impactScope} 插件已启用。` }
        : { status: "unresolved", summary: `${rootCause.impactScope} 插件仍处于禁用状态。` };
    }

    case "primary_model_missing":
    case "primary_model_unavailable": {
      const modelRecovered = signals.models.candidateModelKeys.includes(signals.models.primaryModelKey);

      if (modelRecovered && signals.gateway.reachable === "reachable") {
        return { status: "resolved", summary: "主模型已恢复，Gateway 也可达。" };
      }

      if (modelRecovered) {
        return { status: "partially_resolved", summary: "主模型已恢复，但 Gateway 仍未恢复。" };
      }

      return { status: "unresolved", summary: "主模型问题仍然存在。" };
    }

    case "gateway_unreachable":
    case "gateway_restart_required":
      return signals.gateway.reachable === "reachable"
        ? { status: "resolved", summary: "Gateway 已恢复可达。" }
        : { status: "unresolved", summary: "Gateway 仍不可达。" };

    case "session_log_error_detected":
    case "agent_dispatch_failure": {
      const stillPresent = signals.logs.references.some((reference) => {
        const line = signals.logs.excerpts[reference.lineIndex] ?? "";
        const impactMatched =
          rootCause.impactScope === reference.sessionKey ||
          rootCause.impactScope === reference.sessionId ||
          rootCause.impactScope === reference.agentId;

        return impactMatched && /\berror\b|\bfail(?:ed|ure)?\b|\btimeout\b/i.test(line);
      });

      return stillPresent
        ? { status: "unresolved", summary: "最新日志中仍然存在相同错误信号。" }
        : { status: "resolved", summary: "最新日志中未再检测到相同错误信号。" };
    }

    default:
      return { status: "unresolved", summary: "当前根因缺少自动验证逻辑。" };
  }
}
