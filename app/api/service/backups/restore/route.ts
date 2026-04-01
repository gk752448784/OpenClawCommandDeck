import { NextRequest, NextResponse } from "next/server";

import { buildGatewayRestartCommand } from "@/lib/control/commands";
import { executeCliCommand } from "@/lib/control/execute";
import { restoreServiceBackup } from "@/lib/server/service-backups";

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as {
    backupId?: string;
  };

  if (!body.backupId) {
    return NextResponse.json({ ok: false, error: "缺少 backupId" }, { status: 400 });
  }

  try {
    const restored = await restoreServiceBackup(body.backupId);
    const restart = await executeCliCommand(buildGatewayRestartCommand());
    return NextResponse.json({
      ok: restart.ok,
      restored,
      restart
    }, { status: restart.ok ? 200 : restart.errorCode === "cli_timeout" ? 504 : 500 });
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "恢复备份失败"
      },
      { status: 500 }
    );
  }
}
