import { AppShell } from "@/components/layout/app-shell";
import { DiagnosticsPanel } from "@/components/diagnostics/diagnostics-panel";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";

export default async function DiagnosticsPage() {
  const data = await loadCoreDashboardData();

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="hidden"
    >
      <DiagnosticsPanel />
    </AppShell>
  );
}
