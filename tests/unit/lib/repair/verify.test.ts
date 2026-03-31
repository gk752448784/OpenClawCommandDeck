import { describe, expect, it } from "vitest";

import { verifyRootCauseResolution } from "@/lib/repair/verify";
import type { RootCauseAssessment } from "@/lib/types/issues";
import type { ChannelSignal } from "@/lib/signals/channels";
import type { GatewaySignal } from "@/lib/signals/gateway";
import type { LogSignals } from "@/lib/signals/logs";
import type { ModelSignals } from "@/lib/signals/models";

function createRootCause(
  overrides: Partial<RootCauseAssessment> & Pick<RootCauseAssessment, "type">
): RootCauseAssessment {
  return {
    type: overrides.type,
    severity: overrides.severity ?? "high",
    summary: overrides.summary ?? "summary",
    details: overrides.details ?? "details",
    impactScope: overrides.impactScope ?? "scope",
    evidence: overrides.evidence ?? {
      summary: "summary",
      detail: "detail",
      impactScope: overrides.impactScope ?? "scope"
    }
  };
}

function createSignals(overrides?: {
  channels?: ChannelSignal[];
  models?: ModelSignals;
  gateway?: GatewaySignal;
  logs?: LogSignals;
}) {
  return {
    channels:
      overrides?.channels ??
      [
        {
          channelId: "discord",
          pluginId: "discord",
          channelEnabled: false,
          pluginEnabled: true,
          pluginInstalled: true
        }
      ],
    models:
      overrides?.models ?? {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.3-codex"]
      },
    gateway:
      overrides?.gateway ?? {
        reachable: "unreachable",
        error: "connect ECONNREFUSED 127.0.0.1:18789"
      },
    logs:
      overrides?.logs ?? {
        excerpts: ["error agent=writer session=s-1 dispatch failed timeout waiting gateway"],
        tokens: ["agent", "dispatch", "error", "gateway", "session", "timeout", "writer"],
        references: [
          {
            lineIndex: 0,
            agentId: "writer",
            sessionKey: "writer-main",
            sessionId: "s-1"
          }
        ],
        relatedSessionKeys: ["writer-main"],
        relatedAgentIds: ["writer"]
      }
  };
}

describe("root cause verification", () => {
  it("returns resolved when fresh signals no longer show the issue", () => {
    const result = verifyRootCauseResolution(
      createRootCause({
        type: "channel_disabled",
        impactScope: "discord"
      }),
      createSignals({
        channels: [
          {
            channelId: "discord",
            pluginId: "discord",
            channelEnabled: true,
            pluginEnabled: true,
            pluginInstalled: true
          }
        ]
      })
    );

    expect(result.status).toBe("resolved");
  });

  it("returns partially_resolved when the primary model is repaired but gateway is still down", () => {
    const result = verifyRootCauseResolution(
      createRootCause({
        type: "primary_model_missing",
        impactScope: "openai/gpt-5.4"
      }),
      createSignals({
        models: {
          primaryModelKey: "openai/gpt-5.4",
          candidateModelKeys: ["openai/gpt-5.3-codex", "openai/gpt-5.4"]
        },
        gateway: {
          reachable: "unreachable",
          error: "connect ECONNREFUSED 127.0.0.1:18789"
        }
      })
    );

    expect(result.status).toBe("partially_resolved");
  });

  it("returns unresolved when fresh signals still show the same failure", () => {
    const result = verifyRootCauseResolution(
      createRootCause({
        type: "session_log_error_detected",
        impactScope: "writer-main"
      }),
      createSignals()
    );

    expect(result.status).toBe("unresolved");
  });
});
