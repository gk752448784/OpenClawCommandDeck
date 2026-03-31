import type { LoadedSession, SessionsSnapshot } from "@/lib/adapters/sessions";
import type { LogSignals } from "@/lib/signals/logs";
import type { Issue } from "@/lib/types/issues";

export type SessionRepairSignalItem = {
  id: string;
  agentId: string;
  sessionKey: string;
  severity: Issue["severity"];
  title: string;
  summary: string;
  excerpt: string;
  repairability: Issue["repairPlan"]["repairability"];
  verificationStatus: Issue["verificationStatus"];
};

export type SessionRepairSignalsModel = {
  sessionIssueCounts: Record<string, number>;
  agentIssueCounts: Record<string, number>;
  items: SessionRepairSignalItem[];
};

function relatedLogIssues(issues: Issue[]) {
  return issues.filter(
    (issue) =>
      issue.rootCause.type === "session_log_error_detected" ||
      issue.rootCause.type === "agent_dispatch_failure"
  );
}

function findSessionByScope(sessions: LoadedSession[], scope: string) {
  return (
    sessions.find((session) => session.key === scope) ??
    sessions.find((session) => session.sessionId === scope) ??
    sessions.find((session) => session.agentId === scope) ??
    null
  );
}

function countBy<T extends string>(values: T[]) {
  return values.reduce<Record<string, number>>((counts, value) => {
    counts[value] = (counts[value] ?? 0) + 1;
    return counts;
  }, {});
}

export function buildSessionRepairSignalsModel({
  sessions,
  issues,
  logs
}: {
  sessions: SessionsSnapshot;
  issues: Issue[];
  logs: LogSignals;
}): SessionRepairSignalsModel {
  const items = relatedLogIssues(issues)
    .map((issue) => {
      const scope = issue.rootCause.evidence.impactScope;
      const session = findSessionByScope(sessions.sessions, scope);
      const reference = logs.references.find(
        (item) =>
          item.sessionKey === scope ||
          item.sessionId === scope ||
          item.agentId === scope
      );

      if (!session && !reference) {
        return null;
      }

      return {
        id: issue.id,
        agentId: session?.agentId ?? reference?.agentId ?? "unknown",
        sessionKey: session?.key ?? reference?.sessionKey ?? scope,
        severity: issue.severity,
        title: issue.title,
        summary: issue.summary,
        excerpt:
          reference != null ? logs.excerpts[reference.lineIndex] ?? issue.rootCause.evidence.summary : issue.rootCause.evidence.summary,
        repairability: issue.repairPlan.repairability,
        verificationStatus: issue.verificationStatus
      } satisfies SessionRepairSignalItem;
    })
    .filter((item): item is SessionRepairSignalItem => item != null);

  return {
    sessionIssueCounts: countBy(items.map((item) => item.sessionKey)),
    agentIssueCounts: countBy(items.map((item) => item.agentId)),
    items
  };
}
