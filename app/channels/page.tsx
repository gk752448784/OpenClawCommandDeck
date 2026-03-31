import { AppShell } from "@/components/layout/app-shell";
import { ChannelsOverview } from "@/components/channels/channels-overview";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";
import { SectionCard } from "@/components/shared/section-card";

export default async function ChannelsPage() {
  const data = await loadCoreDashboardData();

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="hidden"
    >
      <SectionCard
        title="消息渠道"
        subtitle="接入与状态"
      >
        <ChannelsOverview channels={data.channels} />
      </SectionCard>
    </AppShell>
  );
}
