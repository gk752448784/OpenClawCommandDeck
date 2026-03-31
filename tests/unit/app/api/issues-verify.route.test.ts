import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const loadIssueSignals = vi.fn();

vi.mock("@/lib/server/load-dashboard-data", () => ({
  loadIssueSignals
}));

describe("POST /api/issues/[issueId]/verify", () => {
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
        excerpts: [],
        tokens: [],
        references: [],
        relatedSessionKeys: [],
        relatedAgentIds: []
      }
    });
  });

  it("returns verification state for the requested issue", async () => {
    const { POST } = await import("@/app/api/issues/[issueId]/verify/route");
    const request = new NextRequest(
      "http://localhost/api/issues/config:gateway_unreachable:gateway/verify",
      {
        method: "POST"
      }
    );

    const response = await POST(request, {
      params: Promise.resolve({ issueId: "config:gateway_unreachable:gateway" })
    });
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.status).toBe("unresolved");
    expect(typeof payload.summary).toBe("string");
  });
});
