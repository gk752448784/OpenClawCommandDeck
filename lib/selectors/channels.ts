import type { HealthState } from "@/lib/types/view-models";
import type { OpenClawConfig } from "@/lib/validators/openclaw-config";

export type ChannelSummary = {
  id: string;
  label: string;
  enabled: boolean;
  health: Exclude<HealthState, "critical">;
  category: "主渠道" | "插件渠道";
  summary: string;
  highlights: string[];
  recommendedAction: string;
  version?: string;
  extension?: {
    id: string;
    label: string;
    enabled: boolean;
    version?: string;
  };
};

function buildFeishuSummary(config: OpenClawConfig): ChannelSummary {
  const channel = config.channels.feishu;
  const plugin = config.plugins.entries?.["openclaw-lark"];
  const install = config.plugins.installs?.["openclaw-lark"];

  const enabled = channel?.enabled ?? false;
  const extensionEnabled = plugin?.enabled ?? false;
  const groupPolicy = channel?.groupPolicy ?? "未设置";
  const connectionMode = channel?.connectionMode ?? "未设置";
  const domain = channel?.domain ?? "默认域";
  const highlights = [
    `连接方式：${connectionMode}`,
    `群策略：${groupPolicy}`,
    `域名：${domain}`,
    extensionEnabled
      ? `扩展：已启用${install?.version ? ` · ${install.version}` : ""}`
      : "扩展：未启用"
  ];

  const health =
    enabled && extensionEnabled && groupPolicy !== "open" ? "healthy" : "warning";

  const recommendedAction = !enabled
    ? "启用飞书主渠道，恢复当前工作入口。"
    : !extensionEnabled
      ? "启用飞书扩展，补齐文档、知识库和开放平台能力。"
      : groupPolicy === "open"
        ? "将群策略从 open 调整为 allowlist，降低误触发和注入风险。"
        : "飞书链路完整，可继续用于主入口和文档协同。";

  return {
    id: "feishu",
    label: "飞书",
    enabled,
    health,
    category: "主渠道",
    summary: enabled ? "当前主入口，承接消息和协同能力。" : "当前主入口已停用。",
    highlights,
    recommendedAction,
    extension: {
      id: "openclaw-lark",
      label: "飞书扩展",
      enabled: extensionEnabled,
      version: install?.version
    }
  };
}

function buildWeixinSummary(config: OpenClawConfig): ChannelSummary {
  const plugin = config.plugins.entries?.["openclaw-weixin"];
  const install = config.plugins.installs?.["openclaw-weixin"];
  const enabled = plugin?.enabled ?? false;

  return {
    id: "openclaw-weixin",
    label: "微信",
    enabled,
    health: enabled ? "healthy" : "warning",
    category: "插件渠道",
    summary: enabled
      ? "适合直连和补充触达，当前作为辅助入口。"
      : "当前未启用微信触达。",
    highlights: [
      "接入方式：插件",
      `安装版本：${install?.version ?? "未安装"}`,
      enabled ? "状态：可收发" : "状态：待启用"
    ],
    recommendedAction: enabled
      ? "保持作为补充触达入口，重点看二维码登录和连接稳定性。"
      : "启用微信插件，恢复辅助通知与私聊入口。",
    version: install?.version
  };
}

function buildDiscordSummary(config: OpenClawConfig): ChannelSummary {
  const channel = config.channels.discord;
  const plugin = config.plugins.entries?.discord;
  const enabled = (channel?.enabled ?? false) && (plugin?.enabled ?? true);
  const policy = channel?.groupPolicy ?? "未设置";
  const health = enabled && policy === "allowlist" ? "healthy" : "warning";

  return {
    id: "discord",
    label: "Discord",
    enabled,
    health,
    category: "主渠道",
    summary: enabled ? "适合作为开放社区或远程辅助入口。" : "当前未启用 Discord 渠道。",
    highlights: [
      `群策略：${policy}`,
      `流式输出：${String(channel?.streaming ?? "未设置")}`,
      plugin?.enabled === false ? "插件入口：未启用" : "插件入口：已启用"
    ],
    recommendedAction: !enabled
      ? "启用 Discord，补齐远程和社区入口。"
      : policy !== "allowlist"
        ? "将 Discord 的群策略调整为 allowlist，避免频道过度暴露。"
        : "Discord 配置合理，可作为低频远程入口保留。",
    extension: {
      id: "discord",
      label: "Discord 插件入口",
      enabled: plugin?.enabled ?? true
    }
  };
}

export function buildChannelsSummary(config: OpenClawConfig): ChannelSummary[] {
  return [
    buildFeishuSummary(config),
    buildWeixinSummary(config),
    buildDiscordSummary(config)
  ];
}
