import { describe, expect, it } from "vitest";

import { buildChannelsSummary } from "@/lib/selectors/channels";
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
      discord: {
        enabled: true,
        groupPolicy: "allowlist",
        streaming: "off"
      },
      feishu: {
        enabled: true,
        connectionMode: "websocket",
        domain: "feishu",
        groupPolicy: "open",
        streaming: true
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
          enabled: true
        },
        "openclaw-lark": {
          enabled: true
        },
        "openclaw-weixin": {
          enabled: true
        }
      },
      installs: {
        "openclaw-lark": {
          version: "2026.3.15"
        },
        "openclaw-weixin": {
          version: "1.0.3"
        }
      }
    },
    ...overrides
  } as OpenClawConfig;
}

describe("channels selector", () => {
  it("builds three product-level channel cards from local config", () => {
    const model = buildChannelsSummary(createConfig());

    expect(model).toHaveLength(3);
    expect(model.map((item) => item.label)).toEqual(["飞书", "微信", "Discord"]);
    expect(model[0]).toMatchObject({
      id: "feishu",
      enabled: true,
      health: "warning"
    });
    expect(model[0]?.highlights.some((item) => item.includes("websocket"))).toBe(true);
    expect(model[0]?.highlights.some((item) => item.includes("扩展"))).toBe(true);
    expect(model[1]).toMatchObject({
      id: "openclaw-weixin",
      enabled: true,
      version: "1.0.3"
    });
    expect(model[2]?.highlights.some((item) => item.includes("allowlist"))).toBe(true);
  });

  it("marks channels as warning when core channel or extension is inconsistent", () => {
    const model = buildChannelsSummary(
      createConfig({
        channels: {
          discord: {
            enabled: false,
            groupPolicy: "open"
          },
          feishu: {
            enabled: true,
            connectionMode: "websocket",
            domain: "feishu",
            groupPolicy: "allowlist"
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
            },
            "openclaw-weixin": {
              enabled: false
            }
          },
          installs: {}
        }
      })
    );

    expect(model.find((item) => item.id === "feishu")?.health).toBe("warning");
    expect(model.find((item) => item.id === "feishu")?.recommendedAction).toContain(
      "启用飞书扩展"
    );
    expect(model.find((item) => item.id === "openclaw-weixin")?.enabled).toBe(false);
    expect(model.find((item) => item.id === "discord")?.recommendedAction).toContain(
      "启用 Discord"
    );
  });
});
