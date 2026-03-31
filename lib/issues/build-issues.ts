import { buildRepairPlanForRootCause } from "@/lib/repair/plans";
import { verifyRootCauseResolution } from "@/lib/repair/verify";
import { classifyChannelRootCauses } from "@/lib/root-causes/channels";
import { classifyLogRootCauses } from "@/lib/root-causes/logs";
import { classifyModelRootCauses } from "@/lib/root-causes/models";
import type { IssueSignals } from "@/lib/server/load-dashboard-data";
import type { Issue, IssueSource, RootCauseAssessment } from "@/lib/types/issues";

function issueSourceForRootCause(rootCause: RootCauseAssessment): IssueSource {
  switch (rootCause.type) {
    case "channel_disabled":
    case "plugin_disabled":
    case "plugin_missing":
    case "channel_plugin_mismatch":
    case "credential_missing":
    case "unsafe_policy":
      return "Channel";
    case "agent_dispatch_failure":
    case "session_log_error_detected":
      return "Agent";
    default:
      return "Config";
  }
}

export function buildIssueId(rootCause: RootCauseAssessment) {
  return `${issueSourceForRootCause(rootCause).toLowerCase()}:${rootCause.type}:${rootCause.impactScope}`;
}

function toIssue(rootCause: RootCauseAssessment, signals: IssueSignals): Issue {
  return {
    id: buildIssueId(rootCause),
    source: issueSourceForRootCause(rootCause),
    title: rootCause.summary,
    summary: rootCause.details,
    severity: rootCause.severity,
    rootCause: {
      type: rootCause.type,
      evidence: rootCause.evidence
    },
    repairPlan: buildRepairPlanForRootCause(rootCause),
    verificationStatus: verifyRootCauseResolution(rootCause, signals).status
  };
}

export function buildIssues({ signals }: { signals: IssueSignals }): Issue[] {
  const rootCauses = [
    ...classifyChannelRootCauses(signals.channels),
    ...classifyModelRootCauses({
      models: signals.models,
      gateway: signals.gateway
    }),
    ...classifyLogRootCauses(signals.logs)
  ];

  return rootCauses.map((rootCause) => toIssue(rootCause, signals));
}

export function findIssueById({
  issueId,
  signals
}: {
  issueId: string;
  signals: IssueSignals;
}) {
  return buildIssues({ signals }).find((issue) => issue.id === issueId) ?? null;
}
