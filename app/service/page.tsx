import { AppShell } from "@/components/layout/app-shell";
import { ActionButton } from "@/components/control/action-button";
import { BackupsPanel } from "@/components/service/backups-panel";
import { RuntimePanel } from "@/components/service/runtime-panel";
import { SectionCard } from "@/components/shared/section-card";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";

export const dynamic = "force-dynamic";

export default async function ServicePage() {
  const data = await loadCoreDashboardData();

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="compact"
      pageTitle="服务管理"
      pageSubtitle="网关启停、重启与运行态巡检"
    >
      <div className="control-grid">
        <SectionCard title="Gateway 状态" subtitle="来自 openclaw status --json 的实时快照">
          <RuntimePanel />
        </SectionCard>

        <SectionCard title="Gateway 控制" subtitle="高频运维动作集中执行">
          <div className="quick-actions">
            <ActionButton
              action="gateway-start"
              payload={{}}
              label="启动 Gateway"
            />
            <ActionButton
              action="gateway-stop"
              payload={{}}
              label="停止 Gateway"
              variant="secondary"
              confirmMessage="确认停止 Gateway 吗？停止后消息与调度会中断。"
            />
            <ActionButton
              action="gateway-restart"
              payload={{}}
              label="重启 Gateway"
              variant="secondary"
            />
          </div>
        </SectionCard>

        <SectionCard title="配置备份与恢复" subtitle="备份 openclaw 关键配置并支持回滚">
          <BackupsPanel />
        </SectionCard>
      </div>
    </AppShell>
  );
}
