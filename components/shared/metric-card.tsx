export function MetricCard({
  label,
  value,
  hint,
  className,
  variant = "default"
}: {
  label: string;
  value: string;
  hint?: string;
  className?: string;
  variant?: "default" | "quiet";
}) {
  return (
    <article
      className={`metric-card metric-card-${variant}${className ? ` ${className}` : ""}`}
    >
      <span className="metric-label">{label}</span>
      <strong className="metric-value">{value}</strong>
      {hint ? <span className="metric-hint">{hint}</span> : null}
    </article>
  );
}
