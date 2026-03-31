import type { PriorityCard } from "@/lib/types/view-models";
import { SectionCard } from "@/components/shared/section-card";
import { EmptyState } from "@/components/shared/empty-state";

const SOURCE_LABELS: Record<string, string> = {
  main: "主线",
  cron: "计划任务",
  channel: "渠道",
  channels: "渠道",
  agent: "代理",
  agents: "代理",
  config: "配置"
};

function formatSource(source: string) {
  if (source in SOURCE_LABELS) {
    return SOURCE_LABELS[source];
  }

  return "其他来源";
}

export function PriorityCards({ cards }: { cards: PriorityCard[] }) {
  return (
    <SectionCard
      title="优先队列"
      subtitle="当前最需要处理的事项"
      className="deck-section-prominent"
    >
      {cards.length === 0 ? (
        <EmptyState title="没有高优先级事项" description="当前没有需要立即处置的异常，系统处于相对稳定状态。" />
      ) : (
        <div className="priority-grid">
          {cards.map((card) => (
            <article key={card.id} className={`priority-card priority-${card.severity}`}>
              <div className="priority-card-head">
                <div className="priority-meta">
                  <span>{card.type}</span>
                  <span>{formatSource(card.source)}</span>
                </div>
                <span className="priority-severity-label">
                  {card.severity === "high" ? "立即处理" : "持续观察"}
                </span>
              </div>
              <div className="priority-card-body">
                <h3>{card.title}</h3>
                <p>{card.summary}</p>
              </div>
              <footer>
                <span>推荐动作</span>
                <strong>{card.recommendedAction}</strong>
              </footer>
            </article>
          ))}
        </div>
      )}
    </SectionCard>
  );
}
