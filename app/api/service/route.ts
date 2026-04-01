import { NextResponse } from "next/server";

import { loadServiceRuntime } from "@/lib/server/service-runtime";

export async function GET() {
  try {
    const data = await loadServiceRuntime();
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "服务状态加载失败"
      },
      { status: 500 }
    );
  }
}
