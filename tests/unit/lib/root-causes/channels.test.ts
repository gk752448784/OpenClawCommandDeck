import { describe, expect, it } from "vitest";

import { classifyChannelRootCauses } from "@/lib/root-causes/channels";
import { collectChannelSignals } from "@/lib/signals/channels";
import type { OpenClawConfig } from "@/lib/validators/openclaw-config";

function createConfig(overrides?: Partial<OpenClawConfig>): OpenClawConfig {
  return {
    models: {
      providers: {}
    },
    agents: {
      defaults: {
        models: {},
        model: {
          primary: "openai/gpt-5.3-codex"
        },
        workspace: "/tmp/workspace"
      },
      list: []
    },
    channels: {
      feishu: {
        enabled: true,
        connectionMode: "websocket",
        domain: "feishu",
        groupPolicy: "allowlist",
        streaming: true
      },
      discord: {
        enabled: false,
        groupPolicy: "open",
        streaming: false
      }
    },
    gateway: {
      port: 18789,
      mode: "single",
      bind: "127.0.0.1",
      auth: {
        mode: "token"
      }
    },
    plugins: {
      allow: ["discord", "openclaw-lark", "openclaw-weixin"],
      entries: {
        discord: {
          enabled: false
        },
        "openclaw-lark": {
          enabled: true
        },
        "openclaw-weixin": {
          enabled: true
        }
      },
      installs: {
        discord: {
          version: "0.9.1"
        },
        "openclaw-lark": {
          version: "2026.3.15"
        }
      }
    },
    ...overrides
  } as OpenClawConfig;
}

describe("channel signal collector", () => {
  it("extracts channel enabled state and plugin enabled/install states", () => {
    const signals = collectChannelSignals(createConfig());

    expect(signals).toEqual([
      {
        channelId: "feishu",
        pluginId: "openclaw-lark",
        channelEnabled: true,
        pluginEnabled: true,
        pluginInstalled: true
      },
      {
        channelId: "discord",
        pluginId: "discord",
        channelEnabled: false,
        pluginEnabled: false,
        pluginInstalled: true
      },
      {
        channelId: "openclaw-weixin",
        pluginId: "openclaw-weixin",
        channelEnabled: null,
        pluginEnabled: true,
        pluginInstalled: false
      }
    ]);
  });

  it("preserves missing plugin entry as unknown pluginEnabled state", () => {
    const signals = collectChannelSignals(
      createConfig({
        plugins: {
          allow: ["discord", "openclaw-lark", "openclaw-weixin"],
          entries: {
            "openclaw-lark": {
              enabled: true
            },
            "openclaw-weixin": {
              enabled: true
            }
          },
          installs: {
            discord: {
              version: "0.9.1"
            }
          }
        }
      })
    );

    expect(signals.find((signal) => signal.pluginId === "discord")).toEqual({
      channelId: "discord",
      pluginId: "discord",
      channelEnabled: false,
      pluginEnabled: null,
      pluginInstalled: true
    });
  });

  it("classifies plugin-disabled and channel-plugin-mismatch root causes", () => {
    const rootCauses = classifyChannelRootCauses(
      collectChannelSignals(
        createConfig({
          channels: {
            feishu: {
              enabled: false
            },
            discord: {
              enabled: true
            }
          },
          plugins: {
            allow: ["discord", "openclaw-lark", "openclaw-weixin"],
            entries: {
              discord: {
                enabled: false
              },
              "openclaw-lark": {
                enabled: false
              }
            },
            installs: {
              discord: {
                version: "0.9.1"
              },
              "openclaw-lark": {
                version: "2026.3.15"
              }
            }
          }
        })
      )
    );

    expect(rootCauses).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: "channel_plugin_mismatch",
          severity: "high",
          impactScope: "discord"
        }),
        expect.objectContaining({
          type: "plugin_disabled",
          severity: "medium",
          impactScope: "feishu"
        })
      ])
    );
  });
});
