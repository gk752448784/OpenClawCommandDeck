import { buildGatewayRestartCommand } from "@/lib/control/commands";
import { executeCliCommand } from "@/lib/control/execute";

/** 设为 `1` 或 `true` 时，保存/切换模型后不执行 `openclaw gateway restart`（例如 CI）。 */
export function isGatewayRestartAfterModelChangeDisabledByEnv(): boolean {
  const v = process.env.OPENCLAW_SKIP_GATEWAY_RESTART_ON_MODEL_CHANGE;
  return v === "1" || v === "true";
}

export type GatewayRestartOutcome =
  | { ran: false }
  | { ran: true; ok: boolean; stdout: string; stderr: string };

export async function restartGatewayAfterModelChange(): Promise<GatewayRestartOutcome> {
  if (isGatewayRestartAfterModelChangeDisabledByEnv()) {
    return { ran: false };
  }
  const r = await executeCliCommand(buildGatewayRestartCommand());
  return { ran: true, ok: r.ok, stdout: r.stdout, stderr: r.stderr };
}
