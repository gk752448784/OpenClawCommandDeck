import { VerificationBadge } from "@/components/issues/verification-badge";
import type { SessionRepairSignalItem } from "@/lib/selectors/session-repair-signals";

export function SessionLogPanel({ items }: { items: SessionRepairSignalItem[] }) {
  return (
    <div className="alerts-overview-list">
      {items.length > 0 ? (
        items.map((item) => (
          <article key={item.id} className={`alerts-overview-item alert-item alert-item-${item.severity}`}>
            <div className="alert-item-top">
              <div>
                <div className="alert-item-meta">
                  <span>{item.agentId}</span>
                  <span>{item.sessionKey}</span>
                  <span>{item.repairability}</span>
                </div>
                <h3>{item.title}</h3>
              </div>
              <VerificationBadge status={item.verificationStatus} />
            </div>
            <p className="alert-item-summary">{item.summary}</p>
            <pre className="action-log">{item.excerpt}</pre>
          </article>
        ))
      ) : (
        <p className="empty-state-copy">最近的会话日志里还没有识别到需要修复的异常线索。</p>
      )}
    </div>
  );
}
