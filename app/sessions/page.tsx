import { AppShell } from "@/components/layout/app-shell";
import { SessionLogPanel } from "@/components/sessions/session-log-panel";
import { SectionCard } from "@/components/shared/section-card";
import { buildIssues } from "@/lib/issues/build-issues";
import { buildSessionRepairSignalsModel } from "@/lib/selectors/session-repair-signals";
import { loadCoreDashboardData, loadIssueSignals } from "@/lib/server/load-dashboard-data";
import { loadSessionsSnapshot } from "@/lib/adapters/sessions";
import { OPENCLAW_ROOT } from "@/lib/config";
import { buildSessionsModel } from "@/lib/selectors/sessions";

export const dynamic = "force-dynamic";

export default async function SessionsPage() {
  const data = await loadCoreDashboardData();
  const sessionsResult = await loadSessionsSnapshot(
    OPENCLAW_ROOT,
    data.agents.map((agent) => agent.id)
  );
  const issueSignals = sessionsResult.ok ? await loadIssueSignals({
    core: data,
    sessions: sessionsResult.data,
    includeDiagnostics: false
  }) : {
    channels: [],
    models: {
      primaryModelKey: data.config.agents.defaults.model.primary,
      candidateModelKeys: []
    },
    gateway: {
      reachable: "unknown" as const,
      error: null
    },
    logs: {
      excerpts: [],
      tokens: [],
      references: [],
      relatedSessionKeys: [],
      relatedAgentIds: []
    }
  };
  const issues = buildIssues({ signals: issueSignals });
  const sessions = sessionsResult.ok ? buildSessionsModel(sessionsResult.data) : {
    total: 0,
    activeSummary: "0/0 活跃",
    items: []
  };
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
      <SectionCard title="会话监控" subtitle="查看最近活跃会话、来源和上下文占用">
        <table className="data-table">
          <thead>
            <tr>
              <th>代理</th>
              <th>来源</th>
              <th>类型</th>
              <th>模型</th>
              <th>最近更新时间</th>
              <th>上下文占用</th>
              <th>异常线索</th>
              <th>状态</th>
            </tr>
          </thead>
          <tbody>
            {sessions.items.map((item) => (
              <tr key={item.id}>
                <td>{item.agentId}</td>
                <td>{item.channel}</td>
                <td>{item.kind}</td>
                <td>{item.model}</td>
                <td>{item.ageLabel}</td>
                <td>{item.percentUsed}</td>
                <td>{sessionRepairSignals.agentIssueCounts[item.agentId] ?? 0} 条</td>
                <td>{item.status === "active" ? "活跃" : "待机"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </SectionCard>

      <SectionCard
        title="日志与修复线索"
        subtitle="把会话/代理错误摘录、根因和修复级别放在同一处看"
      >
        <SessionLogPanel items={sessionRepairSignals.items} />
      </SectionCard>
    </AppShell>
  );
}
