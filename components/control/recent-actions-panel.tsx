"use client";

import { useEffect, useState } from "react";

import {
  getActionHistory,
  type ActionHistoryEntry
} from "@/components/control/action-history";

function formatTime(timestamp: number) {
  return new Intl.DateTimeFormat("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).format(timestamp);
}

export function RecentActionsPanel() {
  const [items, setItems] = useState<ActionHistoryEntry[]>([]);

  useEffect(() => {
    const refresh = () => setItems(getActionHistory());
    refresh();
    window.addEventListener("commanddeck:action-history-updated", refresh);
    return () => {
      window.removeEventListener("commanddeck:action-history-updated", refresh);
    };
  }, []);

  return (
    <section className="control-zone control-zone-secondary control-recent-actions">
      <header className="control-zone-header">
        <div>
          <p className="eyebrow">留痕</p>
          <h2>最近操作</h2>
          <p>控制动作会在这里留痕，方便回看成败和返回信息。</p>
        </div>
      </header>
      {items.length === 0 ? (
        <div className="empty-state control-empty-state">
          <strong>还没有最近操作</strong>
          <p>你在控制台执行的动作会显示在这里。</p>
        </div>
      ) : (
        <div className="control-history-list">
          {items.map((item) => (
            <article key={item.id} className={`control-history-item control-history-item-${item.status}`}>
              <div className="priority-meta">
                <span>{item.status === "success" ? "成功" : "失败"}</span>
                <span>{formatTime(item.createdAt)}</span>
              </div>
              <h3>{item.label}</h3>
              <p>{item.detail}</p>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
