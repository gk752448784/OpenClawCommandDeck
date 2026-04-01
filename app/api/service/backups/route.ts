import { NextResponse } from "next/server";

import { createServiceBackup, listServiceBackups } from "@/lib/server/service-backups";

export async function GET() {
  const backups = await listServiceBackups();
  return NextResponse.json({ items: backups });
}

export async function POST() {
  try {
    const backup = await createServiceBackup();
    return NextResponse.json({ ok: true, backup });
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "创建备份失败"
      },
      { status: 500 }
    );
  }
}
