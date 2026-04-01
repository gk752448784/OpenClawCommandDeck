import { beforeEach, describe, expect, it, vi } from "vitest";

const loadSkillsDashboardData = vi.fn();

vi.mock("@/lib/server/skills", () => ({
  loadSkillsDashboardData
}));

describe("GET /api/skills", () => {
  beforeEach(() => {
    loadSkillsDashboardData.mockResolvedValue({
      workspaceDir: "/home/cloud/.openclaw/workspace",
      managedSkillsDir: "/home/cloud/.openclaw/skills",
      summary: {
        total: 77,
        eligible: 35,
        disabled: 0,
        blocked: 0,
        missingRequirements: 42
      },
      skills: [
        {
          name: "clawhub",
          description: "Use the ClawHub CLI to search and install skills.",
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
        }
      ]
    });
  });

  it("returns the skills dashboard payload", async () => {
    const { GET } = await import("@/app/api/skills/route");
    const response = await GET();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.summary.total).toBe(77);
    expect(payload.skills[0].name).toBe("clawhub");
    expect(payload.managedSkillsDir).toContain(".openclaw/skills");
  });
});
