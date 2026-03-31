import type { OpenClawConfig } from "@/lib/validators/openclaw-config";

export type ChannelSignal = {
  channelId: string;
  pluginId: string;
  channelEnabled: boolean | null;
  pluginEnabled: boolean | null;
  pluginInstalled: boolean;
};

type ChannelPluginMapping = {
  channelId: string;
  pluginId: string;
  channelEnabled: (config: OpenClawConfig) => boolean | null;
};

const CHANNEL_PLUGIN_MAPPINGS: ChannelPluginMapping[] = [
  {
    channelId: "feishu",
    pluginId: "openclaw-lark",
    channelEnabled: (config) =>
      typeof config.channels.feishu?.enabled === "boolean" ? config.channels.feishu.enabled : null
  },
  {
    channelId: "discord",
    pluginId: "discord",
    channelEnabled: (config) =>
      typeof config.channels.discord?.enabled === "boolean" ? config.channels.discord.enabled : null
  },
  {
    channelId: "openclaw-weixin",
    pluginId: "openclaw-weixin",
    channelEnabled: () => null
  }
];

export function collectChannelSignals(config: OpenClawConfig): ChannelSignal[] {
  return CHANNEL_PLUGIN_MAPPINGS.map((mapping) => {
    const pluginEnabled = config.plugins?.entries?.[mapping.pluginId]?.enabled;

    return {
      channelId: mapping.channelId,
      pluginId: mapping.pluginId,
      channelEnabled: mapping.channelEnabled(config),
      pluginEnabled: typeof pluginEnabled === "boolean" ? pluginEnabled : null,
      pluginInstalled: Boolean(config.plugins?.installs?.[mapping.pluginId])
    };
  });
}
