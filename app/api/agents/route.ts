import { NextResponse } from "next/server";

import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";

export async function GET() {
  const data = await loadCoreDashboardData();
  return NextResponse.json({
    summary: data.agentsSummary,
    agents: data.agents
  });
}
