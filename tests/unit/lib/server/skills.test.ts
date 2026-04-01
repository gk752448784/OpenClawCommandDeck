import { beforeEach, describe, expect, it, vi } from "vitest";

const tryRunOpenClawCli = vi.fn();

vi.mock("@/lib/server/openclaw-cli", async () => {
  const actual = await vi.importActual<typeof import("@/lib/server/openclaw-cli")>(
    "@/lib/server/openclaw-cli"
  );

  return {
    ...actual,
    tryRunOpenClawCli
  };
});

describe("skills server loader", () => {
  beforeEach(() => {
    tryRunOpenClawCli.mockReset();
  });

  it("builds summary from skills list without running skills check", async () => {
    tryRunOpenClawCli.mockResolvedValue({
      ok: true,
      stdout: JSON.stringify({
        workspaceDir: "/home/cloud/.openclaw/workspace",
        managedSkillsDir: "/home/cloud/.openclaw/skills",
        skills: [
          {
            name: "clawhub",
            description: "Install skills",
            eligible: true,
            disabled: false,
            blockedByAllowlist: false,
            source: "openclaw-bundled",
            bundled: true,
            missing: {
              bins: [],
              anyBins: [],
              env: [],
              config: [],
              os: []
            }
          },
          {
            name: "voice-call",
            description: "Calls",
            eligible: false,
            disabled: false,
            blockedByAllowlist: false,
            source: "openclaw-bundled",
            bundled: true,
            missing: {
              bins: [],
              anyBins: [],
              env: [],
              config: ["plugins.entries.voice-call.enabled"],
              os: []
            }
          }
        ]
      }),
      stderr: ""
    });

    const { loadSkillsDashboardData } = await import("@/lib/server/skills");
    const payload = await loadSkillsDashboardData();

    expect(tryRunOpenClawCli).toHaveBeenCalledTimes(1);
    expect(tryRunOpenClawCli).toHaveBeenCalledWith(["skills", "list", "--json"]);
    expect(payload.summary).toEqual({
      total: 2,
      eligible: 1,
      disabled: 0,
      blocked: 0,
      missingRequirements: 1
    });
  });
});
