import type { RootCauseAssessment } from "@/lib/types/issues";
import type { ChannelSignal } from "@/lib/signals/channels";

export function classifyChannelRootCauses(signals: ChannelSignal[]): RootCauseAssessment[] {
  const rootCauses: RootCauseAssessment[] = [];

  for (const signal of signals) {
    if (signal.pluginInstalled === false) {
      rootCauses.push({
        type: "plugin_missing",
        severity: "high",
        summary: `${signal.pluginId} 未安装`,
        details: `未检测到 ${signal.pluginId} 的安装记录。`,
        impactScope: signal.channelId,
        evidence: {
          summary: `${signal.pluginId} 缺少安装记录`,
          detail: `pluginInstalled=false, channelEnabled=${String(signal.channelEnabled)}, pluginEnabled=${String(signal.pluginEnabled)}`,
          impactScope: signal.channelId
        }
      });
      continue;
    }

    if (signal.channelEnabled === true && signal.pluginEnabled === false) {
      rootCauses.push({
        type: "channel_plugin_mismatch",
        severity: "high",
        summary: `${signal.channelId} 渠道已启用但插件被禁用`,
        details: `${signal.channelId} 的渠道开关和插件开关状态不一致。`,
        impactScope: signal.channelId,
        evidence: {
          summary: `${signal.channelId} 渠道与插件状态不一致`,
          detail: `channelEnabled=true, pluginEnabled=false, pluginInstalled=true`,
          impactScope: signal.channelId
        }
      });
      continue;
    }

    if (signal.channelEnabled === true && signal.pluginEnabled === null) {
      rootCauses.push({
        type: "channel_plugin_mismatch",
        severity: "high",
        summary: `${signal.channelId} 渠道已启用但插件状态未知`,
        details: `${signal.channelId} 已启用，但没有找到对应插件 entry 状态。`,
        impactScope: signal.channelId,
        evidence: {
          summary: `${signal.channelId} 缺少插件状态`,
          detail: `channelEnabled=true, pluginEnabled=null, pluginInstalled=true`,
          impactScope: signal.channelId
        }
      });
      continue;
    }

    if (signal.channelEnabled === false && signal.pluginEnabled === true) {
      rootCauses.push({
        type: "channel_disabled",
        severity: "medium",
        summary: `${signal.channelId} 渠道被关闭`,
        details: `${signal.channelId} 插件可用，但渠道开关当前为关闭状态。`,
        impactScope: signal.channelId,
        evidence: {
          summary: `${signal.channelId} 渠道处于关闭状态`,
          detail: `channelEnabled=false, pluginEnabled=true, pluginInstalled=true`,
          impactScope: signal.channelId
        }
      });
      continue;
    }

    if (signal.pluginEnabled === false) {
      rootCauses.push({
        type: "plugin_disabled",
        severity: "medium",
        summary: `${signal.pluginId} 插件被禁用`,
        details: `${signal.pluginId} 已安装但当前处于禁用状态。`,
        impactScope: signal.channelId,
        evidence: {
          summary: `${signal.pluginId} 插件状态为禁用`,
          detail: `channelEnabled=${String(signal.channelEnabled)}, pluginEnabled=false, pluginInstalled=true`,
          impactScope: signal.channelId
        }
      });
    }
  }

  return rootCauses;
}
