import type { ChannelSummary } from "@/lib/selectors/channels";

import { ActionButton } from "@/components/control/action-button";

function StatusBadge({
  enabled,
  health
}: {
  enabled: boolean;
  health: ChannelSummary["health"];
}) {
  if (!enabled) {
    return <span className="status-badge status-warning">未启用</span>;
  }

  return (
    <span
      className={`status-badge ${
        health === "healthy" ? "status-healthy" : "status-warning"
      }`}
    >
      <span className="status-dot" />
      {health === "healthy" ? "运行正常" : "需要调整"}
    </span>
  );
}

function ChannelCard({ channel }: { channel: ChannelSummary }) {
  return (
    <article className="channel-card">
      <div className="channel-card-top">
        <div>
          <div className="channel-card-meta">
            <span>{channel.category}</span>
            {channel.version ? <span>版本 {channel.version}</span> : null}
          </div>
          <h3>{channel.label}</h3>
        </div>
        <StatusBadge enabled={channel.enabled} health={channel.health} />
      </div>

      <p className="channel-card-summary">{channel.summary}</p>

      <div className="channel-highlights">
        {channel.highlights.map((item) => (
          <span key={item} className="channel-highlight">
            {item}
          </span>
        ))}
      </div>

      {channel.extension ? (
        <div className="channel-extension">
          <div>
            <strong>{channel.extension.label}</strong>
            <p>
              {channel.extension.enabled ? "已启用" : "未启用"}
              {channel.extension.version ? ` · ${channel.extension.version}` : ""}
            </p>
          </div>
          <ActionButton
            action="toggle-plugin"
            payload={{
              pluginId: channel.extension.id,
              enabled: !channel.extension.enabled
            }}
            label={channel.extension.enabled ? "停用扩展" : "启用扩展"}
            variant="secondary"
            confirmMessage={
              channel.extension.enabled
                ? `确认停用${channel.extension.label}吗？`
                : `确认启用${channel.extension.label}吗？`
            }
          />
        </div>
      ) : null}

      <div className="channel-card-footer">
        <p>{channel.recommendedAction}</p>
        <div className="inline-actions">
          <ActionButton
            action="toggle-channel"
            payload={{ channelId: channel.id, enabled: !channel.enabled }}
            label={channel.enabled ? "停用渠道" : "启用渠道"}
            variant={channel.enabled ? "secondary" : "default"}
            confirmMessage={
              channel.enabled
                ? `确认停用${channel.label}吗？`
                : `确认启用${channel.label}吗？`
            }
          />
        </div>
      </div>
    </article>
  );
}

export function ChannelsOverview({ channels }: { channels: ChannelSummary[] }) {
  const enabledCount = channels.filter((item) => item.enabled).length;
  const warningCount = channels.filter((item) => item.health === "warning").length;

  return (
    <div className="channels-layout">
      <section className="channels-metrics channels-metrics-compact">
        <div className="metric-card">
          <span className="metric-label">已启用渠道</span>
          <strong className="metric-value">
            {enabledCount}/{channels.length}
          </strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">待调整项</span>
          <strong className="metric-value">{warningCount}</strong>
        </div>
      </section>

      <section className="channels-card-grid">
        {channels.map((channel) => (
          <ChannelCard key={channel.id} channel={channel} />
        ))}
      </section>
    </div>
  );
}
