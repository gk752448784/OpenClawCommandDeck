import { beforeEach, describe, expect, it, vi } from "vitest";

const loadSkillDetails = vi.fn();

vi.mock("@/lib/server/skills", () => ({
  loadSkillDetails
}));

describe("GET /api/skills/[skillName]", () => {
  beforeEach(() => {
    loadSkillDetails.mockResolvedValue({
      name: "voice-call",
      description: "Start voice calls via the OpenClaw voice-call plugin.",
      source: "openclaw-bundled",
      bundled: true,
      filePath: "/tmp/skills/voice-call/SKILL.md",
      baseDir: "/tmp/skills/voice-call",
      skillKey: "voice-call",
      emoji: "📞",
      always: false,
      disabled: false,
      blockedByAllowlist: false,
      eligible: false,
      requirements: {
        bins: [],
        anyBins: [],
        env: [],
        config: ["plugins.entries.voice-call.enabled"],
        os: []
      },
      missing: {
        bins: [],
        anyBins: [],
        env: [],
        config: ["plugins.entries.voice-call.enabled"],
        os: []
      },
      configChecks: [
        {
          path: "plugins.entries.voice-call.enabled",
          satisfied: false
        }
      ],
      install: []
    });
  });

  it("returns skill details for the requested skill", async () => {
    const { GET } = await import("@/app/api/skills/[skillName]/route");
    const response = await GET(new Request("http://localhost/api/skills/voice-call"), {
      params: Promise.resolve({ skillName: "voice-call" })
    });
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(loadSkillDetails).toHaveBeenCalledWith("voice-call");
    expect(payload.skillKey).toBe("voice-call");
    expect(payload.configChecks[0].path).toBe("plugins.entries.voice-call.enabled");
  });
});
