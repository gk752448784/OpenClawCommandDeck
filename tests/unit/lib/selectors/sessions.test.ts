import { describe, expect, it } from "vitest";

import { buildSessionsModel } from "@/lib/selectors/sessions";

describe("sessions selector", () => {
  it("summarizes recent sessions into a workbench-friendly model", () => {
    const model = buildSessionsModel({
      count: 2,
      sessions: [
        {
          sessionId: "session-1",
          key: "agent:main:feishu:direct:ou_123",
          updatedAt: 1774494747291,
          ageMs: 30_000,
          model: "gpt-5.3-codex",
          contextTokens: 272000,
          agentId: "main",
          kind: "direct",
          percentUsed: 20
        },
        {
          sessionId: "session-2",
          key: "agent:main:cron:job-1",
          updatedAt: 1774493208725,
          ageMs: 1_572_022,
          model: "gpt-5.3-codex",
          contextTokens: 272000,
          agentId: "main",
          kind: "direct"
        }
      ]
    });

    expect(model.total).toBe(2);
    expect(model.items[0]?.channel).toBe("feishu");
    expect(model.items[0]?.status).toBe("active");
    expect(model.items[0]?.percentUsed).toBe("20%");
    expect(model.items[1]?.channel).toBe("cron");
  });

  it("builds unique item ids even when sessionId is duplicated", () => {
    const model = buildSessionsModel({
      count: 2,
      sessions: [
        {
          sessionId: "95769b6e-3916-4a6e-bb99-630868f41ea6",
          key: "session:writer:discord:writer-main",
          updatedAt: 1774494747291,
          ageMs: 30_000,
          model: "gpt-5.3-codex",
          agentId: "writer",
          kind: "chat",
          percentUsed: 20
        },
        {
          sessionId: "95769b6e-3916-4a6e-bb99-630868f41ea6",
          key: "session:reviewer:feishu:reviewer-main",
          updatedAt: 1774493208725,
          ageMs: 90_000,
          model: "gpt-5.3-codex",
          agentId: "reviewer",
          kind: "chat",
          percentUsed: 10
        }
      ]
    });

    expect(model.items).toHaveLength(2);
    expect(model.items[0]?.id).not.toBe(model.items[1]?.id);
  });
});
