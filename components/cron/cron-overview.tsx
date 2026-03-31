import type { CronJobs } from "@/lib/validators/cron-jobs";

import { ActionButton } from "@/components/control/action-button";
import { FixCronTargetForm } from "@/components/control/fix-cron-target-form";
import { buildCronDashboardModel } from "@/lib/selectors/cron-dashboard";

function CronStatus({ tone, label }: { tone: "healthy" | "warning"; label: string }) {
  return (
    <span className={`status-badge ${tone === "healthy" ? "status-healthy" : "status-warning"}`}>
      <span className="status-dot" />
      {label}
    </span>
  );
}

export function CronOverview({ cron }: { cron: CronJobs }) {
  const model = buildCronDashboardModel(cron);

  return (
    <div className="management-layout">
      <section className="management-metrics management-metrics-compact">
        <div className="metric-card">
          <span className="metric-label">任务总数</span>
          <strong className="metric-value">{model.summary.total}</strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">已启用</span>
          <strong className="metric-value">{model.summary.enabled}</strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">失败任务</span>
          <strong className="metric-value">{model.summary.failed}</strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">待修复</span>
          <strong className="metric-value">{model.summary.needsRepair}</strong>
        </div>
      </section>

      <section className="management-card-grid">
        {model.items.map((item) => (
          <article key={item.id} className="management-card">
            <div className="management-card-top">
              <div>
                <div className="management-card-meta">
                  <span>{item.agentId}</span>
                  <span>{item.schedule}</span>
                </div>
                <h3>{item.title}</h3>
              </div>
              <CronStatus tone={item.statusTone} label={item.statusLabel} />
            </div>

            <p className="management-card-summary">{item.summary}</p>

            <div className="management-tags">
              <span className="management-tag">投递目标：{item.deliverySummary}</span>
              <span className="management-tag">状态：{item.enabled ? "已启用" : "已停用"}</span>
            </div>

            <div className="management-actions">
              <ActionButton action="run-cron" payload={{ id: item.id }} label="立即执行" />
              <ActionButton
                action="toggle-cron"
                payload={{ id: item.id, enabled: !item.enabled }}
                label={item.enabled ? "停用任务" : "启用任务"}
                variant="secondary"
                confirmMessage={
                  item.enabled
                    ? `确认停用“${item.title}”吗？`
                    : `确认启用“${item.title}”吗？`
                }
              />
            </div>

            {item.needsRepair ? <FixCronTargetForm cronId={item.id} /> : null}
          </article>
        ))}
      </section>
    </div>
  );
}
