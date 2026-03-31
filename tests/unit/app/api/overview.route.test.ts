import { beforeEach, describe, expect, it, vi } from "vitest";

const loadDashboardData = vi.fn();

vi.mock("@/lib/server/load-dashboard-data", () => ({
  loadDashboardData
}));

describe("GET /api/overview", () => {
  beforeEach(() => {
    loadDashboardData.mockResolvedValue({
      overview: {
        topBar: {
          appName: "OpenClaw 工作台"
        },
        priorityCards: [{ id: "1" }],
        roleCards: [{ id: "main" }],
        rightRail: {
          cron: {
            failedCount: 1
          }
        }
      }
    });
  });

  it("returns the dashboard overview payload", async () => {
    const { GET } = await import("@/app/api/overview/route");
    const response = await GET();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.topBar.appName).toBe("OpenClaw 工作台");
    expect(Array.isArray(payload.priorityCards)).toBe(true);
    expect(Array.isArray(payload.roleCards)).toBe(true);
    expect(payload.rightRail.cron.failedCount).toBeGreaterThanOrEqual(1);
  });
});
