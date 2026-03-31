import { NextResponse } from "next/server";

import { loadDashboardData } from "@/lib/server/load-dashboard-data";

export async function GET() {
  const data = await loadDashboardData();
  return NextResponse.json(data.overview);
}
