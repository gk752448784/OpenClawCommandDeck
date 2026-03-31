import type { RoleCard } from "@/lib/types/view-models";
import { SectionCard } from "@/components/shared/section-card";

export function MainAssistantCard({ card }: { card: RoleCard }) {
  return (
    <SectionCard title={card.title} subtitle={card.summary}>
      <div className="role-metrics">
        {card.metrics.map((metric) => (
          <div key={metric.label} className="role-metric">
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
          </div>
        ))}
      </div>
    </SectionCard>
  );
}
