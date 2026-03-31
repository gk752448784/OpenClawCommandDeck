import { NextResponse } from "next/server";

import { loadDiagnosticsData } from "@/lib/server/load-dashboard-data";

export async function GET() {
  try {
    const data = await loadDiagnosticsData();
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "诊断加载失败"
      },
      { status: 500 }
    );
  }
}
