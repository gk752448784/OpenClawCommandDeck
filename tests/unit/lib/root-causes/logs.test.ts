import { describe, expect, it } from "vitest";

import { classifyLogRootCauses } from "@/lib/root-causes/logs";
import { collectGatewaySignal } from "@/lib/signals/gateway";
import { collectLogSignals } from "@/lib/signals/logs";
import type { SessionsSnapshot } from "@/lib/adapters/sessions";

describe("gateway and log signal collectors", () => {
  it("preserves explicit and unknown gateway reachability states", () => {
    const signal = collectGatewaySignal({
      gateway: {
        reachable: false,
        error: "connect ECONNREFUSED 127.0.0.1:18789"
      }
    });

    expect(signal).toEqual({
      reachable: "unreachable",
      error: "connect ECONNREFUSED 127.0.0.1:18789"
    });

    expect(collectGatewaySignal({})).toEqual({
      reachable: "unknown",
      error: null
    });
  });

  it("extracts reusable log evidence and only links explicit session and agent references", () => {
    const sessions: SessionsSnapshot = {
      count: 2,
      sessions: [
        {
          sessionId: "s-1",
          key: "writer-main",
          agentId: "writer",
          model: "openai/gpt-5.3-codex"
        },
        {
          sessionId: "s-2",
          key: "ops-main",
          agentId: "ops",
          model: "openai/gpt-5.3-codex"
        }
      ]
    };

    const signal = collectLogSignals({
      logs: [
        "2026-03-31T10:00:00.000Z info agent=writer session=writer-main dispatch start",
        "2026-03-31T10:00:02.000Z error text mentions writer-mainly and operations but no explicit refs",
        "2026-03-31T10:00:05.000Z warn agent=ops session=s-2 retrying after failure",
        "2026-03-31T10:00:08.000Z info heartbeat ok trace=alpha-beta"
      ],
      sessions
    });

    expect(signal.excerpts).toHaveLength(4);
    expect(signal.references).toEqual([
      {
        lineIndex: 0,
        agentId: "writer",
        sessionKey: "writer-main",
        sessionId: "s-1"
      },
      {
        lineIndex: 2,
        agentId: "ops",
        sessionKey: "ops-main",
        sessionId: "s-2"
      }
    ]);
    expect(signal.tokens).toEqual(
      expect.arrayContaining(["info", "agent", "writer", "session", "writer-main", "dispatch"])
    );
    expect(signal.relatedSessionKeys).toEqual(["ops-main", "writer-main"]);
    expect(signal.relatedAgentIds).toEqual(["ops", "writer"]);
  });

  it("classifies session log errors from explicit troubleshooting evidence", () => {
    const sessions: SessionsSnapshot = {
      count: 1,
      sessions: [
        {
          sessionId: "s-1",
          key: "writer-main",
          agentId: "writer",
          model: "openai/gpt-5.3-codex"
        }
      ]
    };

    const signal = collectLogSignals({
      logs: [
        "2026-03-31T10:00:00.000Z info agent=writer session=s-1 dispatch start",
        "2026-03-31T10:00:02.000Z error agent=writer session=s-1 dispatch failed timeout waiting gateway"
      ],
      sessions
    });

    const rootCauses = classifyLogRootCauses(signal);

    expect(rootCauses).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: "session_log_error_detected",
          severity: "high",
          impactScope: "writer-main"
        })
      ])
    );
  });

  it("classifies gateway restart required from explicit log evidence", () => {
    const sessions: SessionsSnapshot = {
      count: 1,
      sessions: [
        {
          sessionId: "s-1",
          key: "writer-main",
          agentId: "writer",
          model: "openai/gpt-5.3-codex"
        }
      ]
    };

    const signal = collectLogSignals({
      logs: [
        "2026-03-31T10:00:02.000Z warn agent=writer session=s-1 gateway restart required after config drift"
      ],
      sessions
    });

    const rootCauses = classifyLogRootCauses(signal);

    expect(rootCauses).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: "gateway_restart_required",
          severity: "high",
          impactScope: "gateway"
        })
      ])
    );
  });
});
