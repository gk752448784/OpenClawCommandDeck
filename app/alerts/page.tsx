import { AppShell } from "@/components/layout/app-shell";
import { AlertsOverview } from "@/components/alerts/alerts-overview";
import { buildIssues } from "@/lib/issues/build-issues";
import { loadCoreDashboardData, loadIssueSignals } from "@/lib/server/load-dashboard-data";

export default async function AlertsPage() {
  const data = await loadCoreDashboardData();
  const signals = await loadIssueSignals();
  const issues = buildIssues({ signals });

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="compact"
      pageTitle="告警分诊"
      pageSubtitle="只看需要动作的异常"
    >
      <AlertsOverview issues={issues} />
    </AppShell>
  );
}
