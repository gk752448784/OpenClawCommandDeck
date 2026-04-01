import { beforeEach, describe, expect, it, vi } from "vitest";

const listServiceBackups = vi.fn();
const createServiceBackup = vi.fn();

vi.mock("@/lib/server/service-backups", () => ({
  listServiceBackups: (...args: unknown[]) => listServiceBackups(...args),
  createServiceBackup: (...args: unknown[]) => createServiceBackup(...args)
}));

describe("service backups api", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("GET /api/service/backups returns backup list", async () => {
    listServiceBackups.mockResolvedValue([
      {
        id: "20260401T100000Z",
        createdAt: "2026-04-01T10:00:00.000Z",
        fileCount: 3
      }
    ]);
    const { GET } = await import("@/app/api/service/backups/route");
    const response = await GET();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.items).toHaveLength(1);
    expect(payload.items[0].id).toBe("20260401T100000Z");
  });

  it("POST /api/service/backups creates a backup", async () => {
    createServiceBackup.mockResolvedValue({
      id: "20260401T101500Z",
      createdAt: "2026-04-01T10:15:00.000Z",
      files: ["openclaw.json"]
    });
    const { POST } = await import("@/app/api/service/backups/route");
    const response = await POST();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.backup.id).toBe("20260401T101500Z");
  });
});
