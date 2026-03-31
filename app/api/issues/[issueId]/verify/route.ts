import { NextRequest, NextResponse } from "next/server";

import { findIssueById } from "@/lib/issues/build-issues";
import { verifyRootCauseResolution } from "@/lib/repair/verify";
import { loadIssueSignals } from "@/lib/server/load-dashboard-data";

export async function POST(
  _request: NextRequest,
  context: { params: Promise<{ issueId: string }> }
) {
  const { issueId } = await context.params;
  const signals = await loadIssueSignals();
  const issue = findIssueById({ issueId, signals });

  if (!issue) {
    return NextResponse.json({ ok: false, error: "Issue not found" }, { status: 404 });
  }

  const verification = verifyRootCauseResolution(
    {
      type: issue.rootCause.type,
      severity: issue.severity,
      summary: issue.title,
      details: issue.summary,
      impactScope: issue.rootCause.evidence.impactScope,
      evidence: issue.rootCause.evidence
    },
    signals
  );

  return NextResponse.json(verification);
}
