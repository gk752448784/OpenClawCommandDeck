import { AppShell } from "@/components/layout/app-shell";
import { SectionCard } from "@/components/shared/section-card";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";
import { loadSessionsSnapshot } from "@/lib/adapters/sessions";
import { OPENCLAW_ROOT } from "@/lib/config";
import { buildSessionsModel } from "@/lib/selectors/sessions";

export default async function SessionsPage() {
  const data = await loadCoreDashboardData();
  const sessionsResult = await loadSessionsSnapshot(
    OPENCLAW_ROOT,
    data.agents.map((agent) => agent.id)
  );
  const sessions = sessionsResult.ok ? buildSessionsModel(sessionsResult.data) : {
    total: 0,
    activeSummary: "0/0 活跃",
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
                <td>{item.status === "active" ? "活跃" : "待机"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </SectionCard>
    </AppShell>
  );
}
