import { AppShell } from "@/components/layout/app-shell";
import { SectionCard } from "@/components/shared/section-card";
import { AgentsOverview } from "@/components/agents/agents-overview";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";

export default async function AgentsPage() {
  const data = await loadCoreDashboardData();

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="hidden"
    >
      <SectionCard title="Agent 管理" subtitle="角色与工作区">
        <AgentsOverview agents={data.agents} />
      </SectionCard>
    </AppShell>
  );
}
