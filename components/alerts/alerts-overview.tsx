import type { AlertModel } from "@/lib/types/view-models";

import { FixCronTargetForm } from "@/components/control/fix-cron-target-form";
import { buildAlertsDashboardModel } from "@/lib/selectors/alerts-dashboard";

function severityLabel(severity: AlertModel["severity"]) {
  return severity === "high" ? "高优先级" : "中优先级";
}

export function AlertsOverview({ alerts }: { alerts: AlertModel[] }) {
  const model = buildAlertsDashboardModel(alerts);

  return (
    <div className="alerts-overview">
      <section className="alerts-overview-queue">
        <header className="alerts-overview-queue-header">
          <div>
            <p className="eyebrow">待处理异常</p>
            <h2>按优先级从高到低</h2>
            <p>先看可立即修复的项，再处理需要观察的提醒。</p>
          </div>
        </header>

        <div className="alerts-overview-list">
          {model.items.map((alert) => (
            <article key={alert.id} className={`alerts-overview-item alert-item alert-item-${alert.severity}`}>
              <div className="alert-item-top">
                <div>
                  <div className="alert-item-meta">
                    <span>{alert.category}</span>
                    <span>{severityLabel(alert.severity)}</span>
                  </div>
                  <h3>{alert.title}</h3>
                </div>
                <span
                  className={`status-badge ${
                    alert.severity === "high" ? "status-critical" : "status-warning"
                  }`}
                >
                  <span className="status-dot" />
                  {alert.primaryAction}
                </span>
              </div>

              <p className="alert-item-summary">{alert.summary}</p>
              <p className="alert-item-summary">{alert.recommendedAction}</p>

              {alert.needsRepair ? (
                <div className="alerts-overview-form-embed">
                  <FixCronTargetForm cronId={alert.targetId} />
                </div>
              ) : null}
            </article>
          ))}
        </div>
      </section>

      <section className="alerts-overview-hero deck-section deck-section-quiet">
        <div className="alerts-overview-hero-copy">
          <p className="eyebrow">Triage first</p>
          <h2>优先处理 {model.summary.high} 个高优先级告警</h2>
          <p>
            当前共有 {model.summary.total} 条异常，先处理会阻断流程的项，再回头看中优先级提醒。
          </p>
        </div>
        <div className="alerts-overview-metrics">
          <div className="metric-card metric-card-quiet">
            <span className="metric-label">告警总数</span>
            <strong className="metric-value">{model.summary.total}</strong>
          </div>
          <div className="metric-card metric-card-quiet">
            <span className="metric-label">高优先级</span>
            <strong className="metric-value">{model.summary.high}</strong>
          </div>
          <div className="metric-card metric-card-quiet">
            <span className="metric-label">中优先级</span>
            <strong className="metric-value">{model.summary.medium}</strong>
          </div>
        </div>
      </section>
    </div>
  );
}
