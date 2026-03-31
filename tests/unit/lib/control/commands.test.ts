import { describe, expect, it } from "vitest";

import {
  buildToggleCronCommand,
  buildRunCronCommand,
  buildFixCronTargetCommand,
  buildToggleChannelCommand,
  buildTogglePluginCommand,
  buildSwitchModelCommand,
  buildGatewayRestartCommand,
  buildDispatchAgentCommand
} from "@/lib/control/commands";

describe("control command builders", () => {
  it("builds a cron enable command", () => {
    expect(buildToggleCronCommand("job-1", true)).toEqual({
      command: "openclaw",
      args: ["cron", "edit", "job-1", "--enable"]
    });
  });

  it("builds a cron run-now command", () => {
    expect(buildRunCronCommand("job-1")).toEqual({
      command: "openclaw",
      args: ["cron", "run", "job-1", "--expect-final"]
    });
  });

  it("builds a cron fix-target command", () => {
    expect(buildFixCronTargetCommand("job-1", "feishu", "oc_xxx")).toEqual({
      command: "openclaw",
      args: ["cron", "edit", "job-1", "--channel", "feishu", "--to", "oc_xxx"]
    });
  });

  it("builds a channel toggle command against the expected config path", () => {
    expect(buildToggleChannelCommand("feishu", false)).toEqual({
      command: "openclaw",
      args: ["config", "set", "channels.feishu.enabled", "false", "--strict-json"]
    });
    expect(buildToggleChannelCommand("openclaw-weixin", true)).toEqual({
      command: "openclaw",
      args: [
        "config",
        "set",
        "plugins.entries.openclaw-weixin.enabled",
        "true",
        "--strict-json"
      ]
    });
  });

  it("builds a model switch command", () => {
    expect(buildSwitchModelCommand("openai/gpt-5.4")).toEqual({
      command: "openclaw",
      args: [
        "config",
        "set",
        "agents.defaults.model.primary",
        "\"openai/gpt-5.4\"",
        "--strict-json"
      ]
    });
  });

  it("builds a gateway restart command", () => {
    expect(buildGatewayRestartCommand()).toEqual({
      command: "openclaw",
      args: ["gateway", "restart"]
    });
  });

  it("builds a plugin toggle command", () => {
    expect(buildTogglePluginCommand("openclaw-lark", false)).toEqual({
      command: "openclaw",
      args: [
        "config",
        "set",
        "plugins.entries.openclaw-lark.enabled",
        "false",
        "--strict-json"
      ]
    });
  });

  it("builds an agent dispatch command", () => {
    expect(buildDispatchAgentCommand("chief-of-staff", "整理今天待办")).toEqual({
      command: "openclaw",
      args: ["agent", "--agent", "chief-of-staff", "--message", "整理今天待办", "--json"]
    });
  });
});
