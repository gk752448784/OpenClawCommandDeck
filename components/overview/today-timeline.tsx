import type { TimelineItem } from "@/lib/types/view-models";
import { SectionCard } from "@/components/shared/section-card";

export function TodayTimeline({ items }: { items: TimelineItem[] }) {
  return (
    <SectionCard title="今日节奏" subtitle="今天的自动执行点与关键时间线">
      <div className="timeline-list">
        {items.map((item) => (
          <article key={item.id} className="timeline-item">
            <strong>{item.label}</strong>
            <span>{item.schedule}</span>
            <small>{item.type}</small>
          </article>
        ))}
      </div>
    </SectionCard>
  );
}
