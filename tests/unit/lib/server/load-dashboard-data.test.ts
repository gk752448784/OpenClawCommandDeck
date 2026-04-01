import { beforeEach, describe, expect, it, vi } from "vitest";

const loadOpenClawConfig = vi.fn();
const loadCronJobs = vi.fn();
const loadHeartbeatGuide = vi.fn();
const loadAgentDefinitions = vi.fn();
const loadSessionsSnapshot = vi.fn();
const runOpenClawCli = vi.fn();
const tryRunOpenClawCli = vi.fn();

vi.mock("@/lib/adapters/openclaw-config", () => ({
  loadOpenClawConfig
}));

vi.mock("@/lib/adapters/cron-jobs", () => ({
  loadCronJobs
}));

vi.mock("@/lib/adapters/heartbeat", () => ({
  loadHeartbeatGuide
}));

vi.mock("@/lib/adapters/agents", () => ({
  loadAgentDefinitions
}));

vi.mock("@/lib/adapters/sessions", () => ({
  loadSessionsSnapshot
}));

vi.mock("@/lib/server/openclaw-cli", async () => {
  const actual = await vi.importActual<typeof import("@/lib/server/openclaw-cli")>(
    "@/lib/server/openclaw-cli"
  );

  return {
    ...actual,
    runOpenClawCli,
    tryRunOpenClawCli
  };
});

describe("loadIssueSignals", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();

    loadOpenClawConfig.mockResolvedValue({
      ok: true,
      data: {
        models: {
          providers: {}
        },
        agents: {
          defaults: {
            models: {},
            model: {
              primary: "openai/gpt-5.4"
            },
            workspace: "/tmp/workspace"
          },
          list: []
        },
        channels: {},
        gateway: {
          port: 18789,
          mode: "single",
          bind: "127.0.0.1",
          auth: {
            mode: "token"
          }
        },
        plugins: {
          allow: [],
          entries: {},
          installs: {}
        }
      }
    });

    loadCronJobs.mockResolvedValue({
      ok: true,
      data: {
        jobs: []
      }
    });

    loadHeartbeatGuide.mockResolvedValue({
      ok: true,
      data: "HEARTBEAT_OK\n- note"
    });

    loadAgentDefinitions.mockResolvedValue({
      ok: true,
      data: [{ id: "writer", role: "main", title: "writer", workspace: "/tmp/writer" }]
    });

    loadSessionsSnapshot.mockResolvedValue({
      ok: true,
      data: {
        count: 0,
        sessions: []
      }
    });
  });

  it("degrades gracefully when status CLI fails", async () => {
    runOpenClawCli.mockRejectedValue(new Error("status failed"));
    tryRunOpenClawCli.mockResolvedValue({
      ok: true,
      stdout: "",
      stderr: ""
    });

    const { loadIssueSignals } = await import("@/lib/server/load-dashboard-data");
    const signals = await loadIssueSignals();

    expect(signals.gateway).toEqual({
      reachable: "unknown",
      error: null
    });
    expect(signals.logs.excerpts).toEqual([]);
  });
});
