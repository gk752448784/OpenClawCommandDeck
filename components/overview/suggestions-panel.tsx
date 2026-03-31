import type { SuggestionItem } from "@/lib/types/view-models";
import { SectionCard } from "@/components/shared/section-card";

export function SuggestionsPanel({ items }: { items: SuggestionItem[] }) {
  return (
    <SectionCard title="主动建议" subtitle="来自 chief-of-staff 与 second-brain 的建议">
      <div className="suggestions-list">
        {items.map((item) => (
          <article key={item.id} className="suggestion-item">
            <div className="priority-meta">
              <span>{item.source}</span>
            </div>
            <h3>{item.title}</h3>
            <p>{item.summary}</p>
          </article>
        ))}
      </div>
    </SectionCard>
  );
}
