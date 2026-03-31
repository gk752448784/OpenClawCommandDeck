import { NextResponse } from "next/server";

import { buildIssues } from "@/lib/issues/build-issues";
import { loadIssueSignals } from "@/lib/server/load-dashboard-data";

export async function GET() {
  const signals = await loadIssueSignals();
  const issues = buildIssues({ signals });
  return NextResponse.json(issues);
}
