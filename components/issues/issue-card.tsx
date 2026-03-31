import { IssueActions } from "@/components/alerts/issue-actions";
import { VerificationBadge } from "@/components/issues/verification-badge";
import type { Issue } from "@/lib/types/issues";

function severityLabel(severity: Issue["severity"]) {
  return severity === "high" ? "高优先级" : "中优先级";
}

export function IssueCard({
  issue,
  primaryAction,
  repairabilityLabel,
  verificationLabel,
  showActions = true
}: {
  issue: Issue;
  primaryAction: string;
  repairabilityLabel: string;
  verificationLabel: string;
  showActions?: boolean;
}) {
  return (
    <article className={`alerts-overview-item alert-item alert-item-${issue.severity}`}>
      <div className="alert-item-top">
        <div>
          <div className="alert-item-meta">
            <span>{issue.source}</span>
            <span>{severityLabel(issue.severity)}</span>
            <span>{repairabilityLabel}</span>
          </div>
          <h3>{issue.title}</h3>
        </div>
        <div className="issue-card-statuses">
          <span className={`status-badge ${issue.severity === "high" ? "status-critical" : "status-warning"}`}>
            <span className="status-dot" />
            {primaryAction}
          </span>
          <VerificationBadge status={issue.verificationStatus} />
        </div>
      </div>

      <div className="issue-summary-grid">
        <div>
          <p className="issue-section-label">根因</p>
          <p className="alert-item-summary">{issue.rootCause.type}</p>
        </div>
        <div>
          <p className="issue-section-label">验证状态</p>
          <p className="alert-item-summary">{verificationLabel}</p>
        </div>
        <div>
          <p className="issue-section-label">影响范围</p>
          <p className="alert-item-summary">{issue.rootCause.evidence.impactScope}</p>
        </div>
      </div>

      <p className="alert-item-summary">{issue.summary}</p>
      <p className="alert-item-summary">{issue.repairPlan.summary}</p>

      <div className="issue-plan-grid">
        <div>
          <p className="issue-section-label">修复步骤</p>
          <ul className="issue-plan-list">
            {issue.repairPlan.steps.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ul>
        </div>
        <div>
          <p className="issue-section-label">无法自动完成时</p>
          <ul className="issue-plan-list">
            {issue.repairPlan.fallbackManualSteps.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ul>
        </div>
      </div>

      {showActions ? <IssueActions issue={issue} /> : null}
    </article>
  );
}
