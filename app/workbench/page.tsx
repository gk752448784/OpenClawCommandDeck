import { AppShell } from "@/components/layout/app-shell";
import { PriorityCards } from "@/components/overview/priority-cards";
import { SuggestionsPanel } from "@/components/overview/suggestions-panel";
import { TodayTimeline } from "@/components/overview/today-timeline";
import { RightRail } from "@/components/overview/right-rail";
import { StatusBadge } from "@/components/shared/status-badge";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";

export const dynamic = "force-dynamic";

function buildRuntimePosture(health: "healthy" | "warning" | "critical") {
  switch (health) {
    case "healthy":
      return "Stable";
    case "warning":
      return "Warning";
    case "critical":
      return "Critical";
  }
}

export default async function WorkbenchPage() {
  const data = await loadCoreDashboardData();
  const heroQuickActions = data.overview.topBar.quickActions?.slice(0, 2);
  const runtimePosture = buildRuntimePosture(data.overview.topBar.health);
  const priorityCount = data.overview.priorityCards.length;

  return (
    <AppShell topBar={{ ...data.overview.topBar, quickActions: heroQuickActions }} topBarVariant="hero">
      <div className="overview-home mission-control-home">
        <section className="mission-control-posture">
          <div className="mission-control-posture-copy">
            <p className="eyebrow">行动建议</p>
            <h2>{priorityCount > 0 ? "先处理异常，再恢复日常节奏" : "当前没有阻塞项，可维持既有运行节奏"}</h2>
            <p>
              {priorityCount > 0
                ? `当前有 ${priorityCount} 项需要判断或处理的异常。先完成最高优先级处置，再进入常规控制和巡检。`
                : "当前未发现需要立即处置的异常，建议保持巡检并关注下一批计划任务执行。"}
            </p>
          </div>
          <div className="mission-control-posture-side">
            <StatusBadge
              tone={data.overview.topBar.health}
              label={data.overview.topBar.health === "healthy" ? "姿态平稳" : "需要校准"}
            />
            <dl className="mission-control-posture-facts">
              <div>
                <dt>今日告警</dt>
                <dd>{data.overview.topBar.alertsToday}</dd>
              </div>
              <div>
                <dt>在线渠道</dt>
                <dd>
                  {data.overview.topBar.channelSummary.online}/{data.overview.topBar.channelSummary.total}
                </dd>
              </div>
              <div>
                <dt>活跃代理</dt>
                <dd>
                  {data.overview.topBar.agentSummary.active}/{data.overview.topBar.agentSummary.total}
                </dd>
              </div>
            </dl>
          </div>
        </section>

        <section className="system-pulse-strip" aria-label="系统摘要">
          <span>运行姿态</span>
          <strong>{runtimePosture}</strong>
          <span>主模型 {data.overview.topBar.primaryModel}</span>
          <span>时区 {data.overview.topBar.timezone}</span>
        </section>
        <div className="mission-control-grid">
          <div className="mission-control-main">
            <PriorityCards cards={data.overview.priorityCards} />
          </div>
          <RightRail
            model={data.overview.rightRail}
            quickActions={data.overview.topBar.quickActions ?? []}
            primaryModel={data.overview.topBar.primaryModel}
            runtimePosture={runtimePosture}
            runtimeContext={data.overview.topBar.timezone}
          />
        </div>
        <section className="mission-control-continuation">
          <TodayTimeline items={data.overview.todayTimeline} />
          <SuggestionsPanel items={data.overview.suggestions} />
        </section>
      </div>
    </AppShell>
  );
}
