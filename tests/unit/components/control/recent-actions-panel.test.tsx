import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.stubGlobal("React", React);

describe("RecentActionsPanel", () => {
  it("renders as a lightweight action-zone panel", async () => {
    const { RecentActionsPanel } = await import("@/components/control/recent-actions-panel");
    const markup = renderToStaticMarkup(<RecentActionsPanel />);

    expect(markup).toContain("control-recent-actions");
    expect(markup).toContain("最近操作");
    expect(markup).toContain("你在控制台执行的动作会显示在这里。");
  });
});
