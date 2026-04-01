import { NextResponse } from "next/server";

import { loadSkillsDashboardData } from "@/lib/server/skills";

export async function GET() {
  const data = await loadSkillsDashboardData();
  return NextResponse.json(data);
}
