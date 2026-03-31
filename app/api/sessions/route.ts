import { NextResponse } from "next/server";

import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";
import { loadSessionsSnapshot } from "@/lib/adapters/sessions";
import { OPENCLAW_ROOT } from "@/lib/config";
import { buildSessionsModel } from "@/lib/selectors/sessions";

export async function GET() {
  const data = await loadCoreDashboardData();
  const sessionsResult = await loadSessionsSnapshot(
    OPENCLAW_ROOT,
    data.agents.map((agent) => agent.id)
  );

  return NextResponse.json(
    sessionsResult.ok
      ? buildSessionsModel(sessionsResult.data)
      : { total: 0, activeSummary: "0/0 活跃", items: [] }
  );
}
