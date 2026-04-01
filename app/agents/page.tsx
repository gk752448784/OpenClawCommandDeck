import { AppShell } from "@/components/layout/app-shell";
import { SectionCard } from "@/components/shared/section-card";
import { AgentsOverview } from "@/components/agents/agents-overview";
import { buildSessionRepairSignalsModel } from "@/lib/selectors/session-repair-signals";
import { buildIssues } from "@/lib/issues/build-issues";
import { loadCoreDashboardData, loadIssueSignals } from "@/lib/server/load-dashboard-data";
import { loadSessionsSnapshot } from "@/lib/adapters/sessions";
import { OPENCLAW_ROOT } from "@/lib/config";

export const dynamic = "force-dynamic";

export default async function AgentsPage() {
  const data = await loadCoreDashboardData();
  const sessionsResult = await loadSessionsSnapshot(
    OPENCLAW_ROOT,
    data.agents.map((agent) => agent.id)
  );
  const issueSignals = await loadIssueSignals({
    core: data,
    sessions: sessionsResult.ok ? sessionsResult.data : undefined,
    includeDiagnostics: false
  });
  const issues = buildIssues({ signals: issueSignals });
  const sessionRepairSignals = sessionsResult.ok ? buildSessionRepairSignalsModel({
    sessions: sessionsResult.data,
    issues,
    logs: issueSignals.logs
  }) : {
    sessionIssueCounts: {},
    agentIssueCounts: {},
    items: []
  };

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="hidden"
    >
      <SectionCard title="Agent 管理" subtitle="角色与工作区">
        <AgentsOverview agents={data.agents} issueCountsByAgent={sessionRepairSignals.agentIssueCounts} />
      </SectionCard>
    </AppShell>
  );
}
