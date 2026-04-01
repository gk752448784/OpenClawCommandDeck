import { describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const restoreServiceBackup = vi.fn();
const executeCliCommand = vi.fn();

vi.mock("@/lib/server/service-backups", () => ({
  restoreServiceBackup: (...args: unknown[]) => restoreServiceBackup(...args)
}));

vi.mock("@/lib/control/execute", () => ({
  executeCliCommand: (...args: unknown[]) => executeCliCommand(...args)
}));

describe("POST /api/service/backups/restore", () => {
  it("restores a backup and restarts gateway", async () => {
    restoreServiceBackup.mockResolvedValue({
      id: "20260401T100000Z",
      restoredFiles: ["openclaw.json"]
    });
    executeCliCommand.mockResolvedValue({
      ok: true,
      stdout: "restarted",
      stderr: ""
    });
    const { POST } = await import("@/app/api/service/backups/restore/route");
    const response = await POST(
      new NextRequest("http://localhost/api/service/backups/restore", {
        method: "POST",
        body: JSON.stringify({ backupId: "20260401T100000Z" }),
        headers: { "Content-Type": "application/json" }
      })
    );
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(executeCliCommand).toHaveBeenCalled();
  });
});
