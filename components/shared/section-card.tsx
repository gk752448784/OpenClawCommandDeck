export function SectionCard({
  title,
  subtitle,
  className,
  children
}: {
  title: string;
  subtitle?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <section className={`deck-section${className ? ` ${className}` : ""}`}>
      <header className="deck-section-header">
        <div>
          <h2>{title}</h2>
          {subtitle ? <p>{subtitle}</p> : null}
        </div>
      </header>
      {children}
    </section>
  );
}
