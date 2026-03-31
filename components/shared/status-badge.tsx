export function StatusBadge({
  tone,
  label
}: {
  tone: "healthy" | "warning" | "critical";
  label: string;
}) {
  return (
    <span className={`status-badge status-${tone}`}>
      <span className="status-dot" />
      {label}
    </span>
  );
}
