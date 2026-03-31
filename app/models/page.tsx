import path from "node:path";

import { AppShell } from "@/components/layout/app-shell";
import { ModelsDashboard } from "@/components/models/models-dashboard";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { OPENCLAW_ROOT } from "@/lib/config";
import { buildModelsDashboardModel } from "@/lib/selectors/models-dashboard";

export default async function ModelsPage() {
  const data = await loadCoreDashboardData();
  const configResult = await loadOpenClawConfig(path.join(OPENCLAW_ROOT, "openclaw.json"));

  if (!configResult.ok) {
    throw new Error(configResult.error.message);
  }

  return (
    <AppShell topBar={data.overview.topBar} topBarVariant="hidden">
      <ModelsDashboard model={buildModelsDashboardModel(configResult.data)} />
    </AppShell>
  );
}
