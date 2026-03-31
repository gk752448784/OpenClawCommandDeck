import { beforeEach, describe, expect, it, vi } from "vitest";

const loadIssueSignals = vi.fn();

vi.mock("@/lib/server/load-dashboard-data", () => ({
  loadIssueSignals
}));

describe("GET /api/issues", () => {
  beforeEach(() => {
    loadIssueSignals.mockResolvedValue({
      channels: [
        {
          channelId: "discord",
          pluginId: "discord",
          channelEnabled: true,
          pluginEnabled: false,
          pluginInstalled: true
        }
      ],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.3-codex"]
      },
      gateway: {
        reachable: "unreachable",
        error: "connect ECONNREFUSED"
      },
      logs: {
        excerpts: ["error agent=writer session=s-1 dispatch failed timeout waiting gateway"],
        tokens: ["dispatch", "error", "writer-main"],
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
    });
  });

  it("returns the unified issue list payload", async () => {
    const { GET } = await import("@/app/api/issues/route");
    const response = await GET();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(Array.isArray(payload)).toBe(true);
    expect(payload[0]?.id).toBe("channel:channel_plugin_mismatch:discord");
    expect(
      payload.some((issue: { id: string }) => issue.id === "config:gateway_unreachable:gateway")
    ).toBe(true);
  });
});
