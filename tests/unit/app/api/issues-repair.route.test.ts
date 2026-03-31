import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const loadIssueSignals = vi.fn();
const executeCliCommand = vi.fn();

vi.mock("@/lib/server/load-dashboard-data", () => ({
  loadIssueSignals
}));

vi.mock("@/lib/control/execute", () => ({
  executeCliCommand: (...args: unknown[]) => executeCliCommand(...args)
}));

describe("POST /api/issues/[issueId]/repair", () => {
  beforeEach(() => {
    vi.clearAllMocks();

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
    executeCliCommand.mockResolvedValue({
      ok: true,
      stdout: "ok",
      stderr: ""
    });
  });

  it("executes auto repairs without explicit confirmation", async () => {
    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const request = new NextRequest(
      "http://localhost/api/issues/channel:channel_plugin_mismatch:discord/repair",
      {
        method: "POST",
        body: JSON.stringify({ confirm: true }),
        headers: {
          "Content-Type": "application/json"
        }
      }
    );

    const response = await POST(request, {
      params: Promise.resolve({ issueId: "channel:channel_plugin_mismatch:discord" })
    });
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(executeCliCommand).toHaveBeenCalledTimes(1);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["config", "set", "plugins.entries.discord.enabled", "true", "--strict-json"]
    });
  });

  it("executes plugin disabled auto repairs", async () => {
    loadIssueSignals.mockResolvedValueOnce({
      channels: [
        {
          channelId: "discord",
          pluginId: "discord",
          channelEnabled: false,
          pluginEnabled: false,
          pluginInstalled: true
        }
      ],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.4"]
      },
      gateway: {
        reachable: "reachable"
      },
      logs: {
        excerpts: [],
        tokens: [],
        references: [],
        relatedSessionKeys: [],
        relatedAgentIds: []
      }
    });

    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const response = await POST(
      new NextRequest("http://localhost/api/issues/channel:plugin_disabled:discord/repair", {
        method: "POST",
        body: JSON.stringify({ confirm: true }),
        headers: {
          "Content-Type": "application/json"
        }
      }),
      {
        params: Promise.resolve({ issueId: "channel:plugin_disabled:discord" })
      }
    );

    expect(response.status).toBe(200);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["config", "set", "plugins.entries.discord.enabled", "true", "--strict-json"]
    });
  });

  it("resolves channel to plugin mapping before enabling a non-matching plugin id", async () => {
    loadIssueSignals.mockResolvedValueOnce({
      channels: [
        {
          channelId: "feishu",
          pluginId: "openclaw-lark",
          channelEnabled: false,
          pluginEnabled: false,
          pluginInstalled: true
        }
      ],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.4"]
      },
      gateway: {
        reachable: "reachable"
      },
      logs: {
        excerpts: [],
        tokens: [],
        references: [],
        relatedSessionKeys: [],
        relatedAgentIds: []
      }
    });

    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const response = await POST(
      new NextRequest("http://localhost/api/issues/channel:plugin_disabled:feishu/repair", {
        method: "POST",
        body: JSON.stringify({ confirm: true }),
        headers: {
          "Content-Type": "application/json"
        }
      }),
      {
        params: Promise.resolve({ issueId: "channel:plugin_disabled:feishu" })
      }
    );

    expect(response.status).toBe(200);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["config", "set", "plugins.entries.openclaw-lark.enabled", "true", "--strict-json"]
    });
  });

  it("executes channel disabled auto repairs", async () => {
    loadIssueSignals.mockResolvedValueOnce({
      channels: [
        {
          channelId: "discord",
          pluginId: "discord",
          channelEnabled: false,
          pluginEnabled: true,
          pluginInstalled: true
        }
      ],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.4"]
      },
      gateway: {
        reachable: "reachable"
      },
      logs: {
        excerpts: [],
        tokens: [],
        references: [],
        relatedSessionKeys: [],
        relatedAgentIds: []
      }
    });

    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const response = await POST(
      new NextRequest("http://localhost/api/issues/channel:channel_disabled:discord/repair", {
        method: "POST",
        body: JSON.stringify({ confirm: true }),
        headers: {
          "Content-Type": "application/json"
        }
      }),
      {
        params: Promise.resolve({ issueId: "channel:channel_disabled:discord" })
      }
    );

    expect(response.status).toBe(200);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["config", "set", "channels.discord.enabled", "true", "--strict-json"]
    });
  });

  it("rejects confirm-gated repairs without confirmation", async () => {
    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const request = new NextRequest(
      "http://localhost/api/issues/config:gateway_unreachable:gateway/repair",
      {
        method: "POST",
        body: JSON.stringify({ confirm: false }),
        headers: {
          "Content-Type": "application/json"
        }
      }
    );

    const response = await POST(request, {
      params: Promise.resolve({ issueId: "config:gateway_unreachable:gateway" })
    });
    const payload = await response.json();

    expect(response.status).toBe(409);
    expect(payload.ok).toBe(false);
    expect(executeCliCommand).not.toHaveBeenCalled();
  });

  it("executes model switch repairs after confirmation", async () => {
    loadIssueSignals.mockResolvedValueOnce({
      channels: [],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.3-codex", "bltcy/gpt-5.4"]
      },
      gateway: {
        reachable: "reachable"
      },
      logs: {
        excerpts: [],
        tokens: [],
        references: [],
        relatedSessionKeys: [],
        relatedAgentIds: []
      }
    });

    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const response = await POST(
      new NextRequest("http://localhost/api/issues/config:primary_model_missing:openai/gpt-5.4/repair", {
        method: "POST",
        body: JSON.stringify({ confirm: true }),
        headers: {
          "Content-Type": "application/json"
        }
      }),
      {
        params: Promise.resolve({ issueId: "config:primary_model_missing:openai/gpt-5.4" })
      }
    );

    expect(response.status).toBe(200);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: [
        "config",
        "set",
        "agents.defaults.model.primary",
        JSON.stringify("openai/gpt-5.3-codex"),
        "--strict-json"
      ]
    });
  });

  it("executes gateway restart required repairs after confirmation", async () => {
    loadIssueSignals.mockResolvedValueOnce({
      channels: [],
      models: {
        primaryModelKey: "openai/gpt-5.4",
        candidateModelKeys: ["openai/gpt-5.4"]
      },
      gateway: {
        reachable: "reachable"
      },
      logs: {
        excerpts: [
          "warn agent=writer session=s-1 gateway restart required after configuration drift"
        ],
        tokens: ["gateway", "restart", "required"],
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

    const { POST } = await import("@/app/api/issues/[issueId]/repair/route");
    const response = await POST(
      new NextRequest("http://localhost/api/issues/config:gateway_restart_required:gateway/repair", {
        method: "POST",
        body: JSON.stringify({ confirm: true }),
        headers: {
          "Content-Type": "application/json"
        }
      }),
      {
        params: Promise.resolve({ issueId: "config:gateway_restart_required:gateway" })
      }
    );

    expect(response.status).toBe(200);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["gateway", "restart"]
    });
  });
});
