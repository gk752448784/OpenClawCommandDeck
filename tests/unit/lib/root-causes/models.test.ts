import { describe, expect, it } from "vitest";

import { classifyModelRootCauses } from "@/lib/root-causes/models";
import { collectGatewaySignal } from "@/lib/signals/gateway";
import { collectModelSignals } from "@/lib/signals/models";
import type { SessionsSnapshot } from "@/lib/adapters/sessions";
import type { OpenClawConfig } from "@/lib/validators/openclaw-config";

function createConfig(overrides?: Partial<OpenClawConfig>): OpenClawConfig {
  return {
    models: {
      providers: {
        openai: {
          api: "responses",
          models: [
            { id: "openai/gpt-5.3-codex" },
            { id: "openai/gpt-4.1-mini" }
          ]
        },
        anthropic: {
          api: "messages",
          models: [{ id: "anthropic/claude-3.7-sonnet" }]
        }
      }
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
        enabled: true
      },
      discord: {
        enabled: false
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
    plugins: {},
    ...overrides
  } as OpenClawConfig;
}

describe("model signal collector", () => {
  it("extracts primary model key and normalized candidate model keys", () => {
    const sessions: SessionsSnapshot = {
      count: 2,
      sessions: [
        {
          sessionId: "s-1",
          key: "writer-main",
          agentId: "writer",
          model: "openrouter/deepseek-r1"
        },
        {
          sessionId: "s-2",
          key: "ops-main",
          agentId: "ops",
          model: "openai/gpt-5.3-codex"
        }
      ]
    };

    const signal = collectModelSignals({
      config: createConfig(),
      sessions
    });

    expect(signal).toEqual({
      primaryModelKey: "openai/gpt-5.3-codex",
      candidateModelKeys: [
        "anthropic/claude-3.7-sonnet",
        "openai/gpt-4.1-mini",
        "openai/gpt-5.3-codex",
        "openrouter/deepseek-r1"
      ]
    });
  });

  it("classifies primary-model-missing and gateway-unreachable root causes", () => {
    const modelSignal = collectModelSignals({
      config: createConfig({
        agents: {
          defaults: {
            models: {},
            model: {
              primary: "openai/gpt-5.4"
            },
            workspace: "/tmp/workspace"
          },
          list: []
        }
      })
    });
    const gatewaySignal = collectGatewaySignal({
      gateway: {
        reachable: false,
        error: "connect ECONNREFUSED 127.0.0.1:18789"
      }
    });

    const rootCauses = classifyModelRootCauses({
      models: modelSignal,
      gateway: gatewaySignal
    });

    expect(rootCauses).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: "primary_model_missing",
          severity: "high",
          impactScope: "openai/gpt-5.4"
        }),
        expect.objectContaining({
          type: "gateway_unreachable",
          severity: "high",
          impactScope: "gateway"
        })
      ])
    );
  });
});
