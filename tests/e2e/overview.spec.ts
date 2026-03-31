import { test, expect } from "@playwright/test";

test("home page renders the command deck title", async ({ page }) => {
  await page.goto("/workbench");
  await expect(page.getByRole("heading", { name: "OpenClaw 工作台" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "现在要看" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "待处理" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "今日节奏" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "主动建议" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "执行系统" })).toBeVisible();
  await expect(page.getByRole("link", { name: "消息与会话" })).toBeVisible();
  await expect(page.getByRole("link", { name: "设置" })).toBeVisible();
});
