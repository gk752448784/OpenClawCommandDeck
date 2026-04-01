import { describe, expect, it, vi } from "vitest";

const loadServiceRuntime = vi.fn();

vi.mock("@/lib/server/service-runtime", () => ({
  loadServiceRuntime: (...args: unknown[]) => loadServiceRuntime(...args)
}));

describe("GET /api/service", () => {
  it("returns service runtime snapshot", async () => {
    loadServiceRuntime.mockResolvedValue({
      gateway: {
        reachable: "reachable",
        error: null
      },
      version: "1.2.3",
      checkedAt: "2026-04-01T10:00:00.000Z"
    });

    const { GET } = await import("@/app/api/service/route");
    const response = await GET();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.version).toBe("1.2.3");
    expect(payload.gateway.reachable).toBe("reachable");
  });
});
