import { SideNav } from "@/components/layout/side-nav";
import { TopBar } from "@/components/layout/top-bar";
import type { TopBarModel } from "@/lib/types/view-models";

export function AppShell({
  topBar,
  topBarVariant,
  pageTitle,
  pageSubtitle,
  children
}: {
  topBar: TopBarModel;
  topBarVariant?: "hero" | "compact" | "hidden";
  pageTitle?: string;
  pageSubtitle?: string;
  children: React.ReactNode;
}) {
  const resolvedTopBarVariant = topBarVariant ?? "compact";

  return (
    <div className="deck-shell">
      <SideNav />
      <main className="deck-main" data-shell-variant={resolvedTopBarVariant}>
        <div className="deck-main-inner">
          <TopBar model={topBar} variant={resolvedTopBarVariant} pageTitle={pageTitle} pageSubtitle={pageSubtitle} />
          {children}
        </div>
      </main>
    </div>
  );
}
