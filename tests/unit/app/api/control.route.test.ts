import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const executeCliCommand = vi.fn();
const restartGatewayAfterModelChange = vi.fn();

vi.mock("@/lib/control/execute", () => ({
  executeCliCommand: (...args: unknown[]) => executeCliCommand(...args)
}));

vi.mock("@/lib/control/restart-gateway", () => ({
  restartGatewayAfterModelChange: (...args: unknown[]) => restartGatewayAfterModelChange(...args)
}));

describe("POST /api/control/[action]", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    executeCliCommand.mockResolvedValue({
      ok: true,
      stdout: "ok",
      stderr: ""
    });
    restartGatewayAfterModelChange.mockResolvedValue({
      ran: true,
      ok: true,
      stdout: "restarted",
      stderr: ""
    });
  });

  it("executes gateway start action", async () => {
    const { POST } = await import("@/app/api/control/[action]/route");
    const response = await POST(
      new NextRequest("http://localhost/api/control/gateway-start", {
        method: "POST",
        body: JSON.stringify({}),
        headers: { "Content-Type": "application/json" }
      }),
      { params: Promise.resolve({ action: "gateway-start" }) }
    );

    expect(response.status).toBe(200);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["gateway", "start"]
    });
  });

  it("maps timeout control failures to 504", async () => {
    executeCliCommand.mockResolvedValueOnce({
      ok: false,
      stdout: "",
      stderr: "timed out",
      errorCode: "cli_timeout"
    });
    const { POST } = await import("@/app/api/control/[action]/route");
    const response = await POST(
      new NextRequest("http://localhost/api/control/gateway-stop", {
        method: "POST",
        body: JSON.stringify({}),
        headers: { "Content-Type": "application/json" }
      }),
      { params: Promise.resolve({ action: "gateway-stop" }) }
    );

    expect(response.status).toBe(504);
  });
});
