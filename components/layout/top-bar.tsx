import type { TopBarModel } from "@/lib/types/view-models";
import { StatusBadge } from "@/components/shared/status-badge";
import Link from "next/link";

function buildHeroHeadline(model: TopBarModel) {
  if (model.alertsToday > 0) {
    return "告警需先处理";
  }

  if (model.health === "healthy") {
    return "当前运行概况";
  }

  return "运行姿态待校准";
}

export function TopBar({
  model,
  variant = "hero",
  pageTitle,
  pageSubtitle
}: {
  model: TopBarModel;
  variant?: "hero" | "compact" | "hidden";
  pageTitle?: string;
  pageSubtitle?: string;
}) {
  if (variant === "hidden") {
    return null;
  }

  if (variant === "compact") {
    return (
      <header className="top-bar top-bar-compact" data-top-bar-variant="compact">
        <div className="top-bar-compact-main">
          <div className="top-bar-compact-copy">
            <p className="eyebrow">Mission Control</p>
            <h1>{pageTitle ?? model.appName}</h1>
            <p className="top-bar-summary">{pageSubtitle ?? model.statusSummary}</p>
          </div>
          <div className="top-bar-compact-side">
            <StatusBadge
              tone={model.health}
              label={model.health === "healthy" ? "状态平稳" : "需处理"}
            />
            <p className="top-bar-status-note">
              告警 {model.alertsToday} · 渠道 {model.channelSummary.online}/{model.channelSummary.total}
            </p>
          </div>
        </div>
      </header>
    );
  }

  return (
    <header className="top-bar top-bar-hero" data-top-bar-variant="hero">
      <div className="top-bar-main">
        <div className="top-bar-copy">
          <p className="eyebrow">Mission Control</p>
          <h1>{pageTitle ?? buildHeroHeadline(model)}</h1>
          <p className="top-bar-summary">
            {pageSubtitle
              ? pageSubtitle
              : `${model.instanceLabel ? `${model.instanceLabel} · ` : ""}${model.statusSummary}`}
          </p>
          <div className="top-bar-context">
            {model.instanceLabel ? <span>{model.instanceLabel}</span> : null}
            <span>主模型 {model.primaryModel}</span>
            <span>运行时区 {model.timezone}</span>
          </div>
          {model.quickActions?.length ? (
            <div className="top-bar-actions">
              {model.quickActions.map((action) => (
                <Link key={action.href} href={action.href} className="top-bar-action">
                  {action.label}
                </Link>
              ))}
            </div>
          ) : null}
        </div>
        <div className="top-bar-status-wrap">
          <StatusBadge
            tone={model.health}
            label={model.health === "healthy" ? "姿态平稳" : "需要校准"}
          />
          <p className="top-bar-status-note">今日告警 {model.alertsToday}</p>
        </div>
      </div>
    </header>
  );
}
