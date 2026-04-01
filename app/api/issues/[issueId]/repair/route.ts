import { NextRequest, NextResponse } from "next/server";

import { executeCliCommand } from "@/lib/control/execute";
import { findIssueById } from "@/lib/issues/build-issues";
import { resolveRepairCommand } from "@/lib/issues/repair-registry";
import { loadIssueSignals } from "@/lib/server/load-dashboard-data";

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ issueId: string }> }
) {
  const { issueId } = await context.params;
  const body = (await request.json().catch(() => ({}))) as { confirm?: boolean };
  const signals = await loadIssueSignals();
  const issue = findIssueById({ issueId, signals });

  if (!issue) {
    return NextResponse.json({ ok: false, error: "Issue not found" }, { status: 404 });
  }

  if (issue.repairPlan.repairability === "confirm" && body.confirm !== true) {
    return NextResponse.json(
      { ok: false, error: "Confirmation required before executing this repair" },
      { status: 409 }
    );
  }

  const command = resolveRepairCommand(issue, signals);
  if (!command) {
    return NextResponse.json(
      { ok: false, error: "No executable repair action is registered for this issue" },
      { status: 400 }
    );
  }

  const result = await executeCliCommand(command);
  return NextResponse.json(result, {
    status: result.ok ? 200 : result.errorCode === "cli_timeout" ? 504 : 500
  });
}
