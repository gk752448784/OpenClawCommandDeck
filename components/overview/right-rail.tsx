import type { RightRailModel } from "@/lib/types/view-models";
import { SectionCard } from "@/components/shared/section-card";
import { MetricCard } from "@/components/shared/metric-card";
import Link from "next/link";

export function RightRail({
  model,
  quickActions = [],
  primaryModel,
  runtimePosture,
  runtimeContext
}: {
  model: RightRailModel;
  quickActions?: Array<{
    href: string;
    label: string;
  }>;
  primaryModel: string;
  runtimePosture: string;
  runtimeContext: string;
}) {
  const hasQuickActions = quickActions.length > 0;

  return (
    <div className="right-rail">
      <SectionCard title="系统脉冲" subtitle="轻量姿态信号" className="deck-section-quiet">
        <div className="system-pulse-grid">
          <MetricCard
            label="渠道"
            value={`${model.channels.healthyCount}/${model.channels.totalCount}`}
            hint="在线"
            variant="quiet"
          />
          <MetricCard
            label="代理"
            value={`${model.agents.activeCount}/${model.agents.totalCount}`}
            hint="活跃"
            variant="quiet"
          />
          <MetricCard
            label="任务"
            value={`${model.cron.failedCount}`}
            hint="失败"
            variant="quiet"
          />
          <MetricCard label="主模型" value={primaryModel} hint="运行目标" variant="quiet" />
        </div>
        <div className="system-pulse-notes">
          <p className="system-pulse-note">
            运行姿态：{runtimePosture} · {runtimeContext}
          </p>
          {model.heartbeat.notes.length ? (
            <ul className="compact-list">
              {model.heartbeat.notes.map((note) => (
                <li key={note}>{note.replace(/^- /, "")}</li>
              ))}
            </ul>
          ) : null}
        </div>
      </SectionCard>

      {hasQuickActions ? (
        <SectionCard title="快速动作" subtitle="常用入口" className="deck-section-quiet">
          <div className="quick-action-grid">
            {quickActions.map((action) => (
              <Link key={action.href} href={action.href} className="quick-action-card">
                <span className="quick-action-label">{action.label}</span>
                <strong>直达操作面</strong>
                <p>减少中间切换，直接进入当前任务对应的操作页。</p>
              </Link>
            ))}
          </div>
        </SectionCard>
      ) : null}
    </div>
  );
}
