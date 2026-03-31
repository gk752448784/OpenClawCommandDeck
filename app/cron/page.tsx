import { AppShell } from "@/components/layout/app-shell";
import { SectionCard } from "@/components/shared/section-card";
import { CronOverview } from "@/components/cron/cron-overview";
import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { OPENCLAW_ROOT } from "@/lib/config";

export default async function CronPage() {
  const cronResult = await loadCronJobs(`${OPENCLAW_ROOT}/cron/jobs.json`);
  if (!cronResult.ok) {
    throw new Error(cronResult.error.message);
  }

  const { overview } = await import("@/lib/server/load-dashboard-data").then((module) =>
    module.loadCoreDashboardData()
  );

  return (
    <AppShell
      topBar={overview.topBar}
      topBarVariant="hidden"
    >
      <SectionCard title="定时任务" subtitle="执行与修复">
        <CronOverview cron={cronResult.data} />
      </SectionCard>
    </AppShell>
  );
}
