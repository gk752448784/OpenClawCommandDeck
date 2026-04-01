import { AppShell } from "@/components/layout/app-shell";
import { SkillsOverview } from "@/components/skills/skills-overview";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";

export const dynamic = "force-dynamic";

export default async function SkillsPage() {
  const dashboard = await loadCoreDashboardData();

  return (
    <AppShell
      topBar={dashboard.overview.topBar}
      topBarVariant="compact"
      pageTitle="Skills"
      pageSubtitle="当前技能清单与缺失依赖"
    >
      <SkillsOverview />
    </AppShell>
  );
}
