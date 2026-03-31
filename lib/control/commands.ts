export type CliCommand = {
  command: string;
  args: string[];
};

export function buildToggleCronCommand(id: string, enabled: boolean): CliCommand {
  return {
    command: "openclaw",
    args: ["cron", "edit", id, enabled ? "--enable" : "--disable"]
  };
}

export function buildRunCronCommand(id: string): CliCommand {
  return {
    command: "openclaw",
    args: ["cron", "run", id, "--expect-final"]
  };
}

export function buildFixCronTargetCommand(
  id: string,
  channel: string,
  target: string
): CliCommand {
  return {
    command: "openclaw",
    args: ["cron", "edit", id, "--channel", channel, "--to", target]
  };
}

function channelConfigPath(channelId: string) {
  if (channelId === "openclaw-weixin") {
    return "plugins.entries.openclaw-weixin.enabled";
  }
  return `channels.${channelId}.enabled`;
}

export function buildToggleChannelCommand(
  channelId: string,
  enabled: boolean
): CliCommand {
  return {
    command: "openclaw",
    args: [
      "config",
      "set",
      channelConfigPath(channelId),
      enabled ? "true" : "false",
      "--strict-json"
    ]
  };
}

export function buildTogglePluginCommand(pluginId: string, enabled: boolean): CliCommand {
  return {
    command: "openclaw",
    args: [
      "config",
      "set",
      `plugins.entries.${pluginId}.enabled`,
      enabled ? "true" : "false",
      "--strict-json"
    ]
  };
}

export function buildSwitchModelCommand(model: string): CliCommand {
  return {
    command: "openclaw",
    args: [
      "config",
      "set",
      "agents.defaults.model.primary",
      JSON.stringify(model),
      "--strict-json"
    ]
  };
}

export function buildGatewayRestartCommand(): CliCommand {
  return {
    command: "openclaw",
    args: ["gateway", "restart"]
  };
}

export function buildDispatchAgentCommand(
  agentId: string,
  message: string
): CliCommand {
  return {
    command: "openclaw",
    args: ["agent", "--agent", agentId, "--message", message, "--json"]
  };
}
