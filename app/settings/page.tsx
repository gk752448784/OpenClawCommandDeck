import path from "node:path";
import Link from "next/link";

import { AppShell } from "@/components/layout/app-shell";
import { SectionCard } from "@/components/shared/section-card";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { OPENCLAW_ROOT } from "@/lib/config";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const data = await loadCoreDashboardData();
  const configResult = await loadOpenClawConfig(path.join(OPENCLAW_ROOT, "openclaw.json"));

  if (!configResult.ok) {
    throw new Error(configResult.error.message);
  }

  const config = configResult.data;
  const providerNames = Object.keys(config.models.providers);
  const enabledChannels = data.channels.filter((channel) => channel.enabled).map((channel) => channel.label);

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="hidden"
    >
      <div className="settings-grid">
        <SectionCard title="模型与服务商" subtitle="跳转到独立菜单管理">
          <div className="workbench-list">
            <article className="priority-card">
              <h3>当前默认模型</h3>
              <p>{config.agents.defaults.model.primary}</p>
            </article>
            <div className="inline-actions">
              <Link href="/models" className="top-bar-link top-bar-link-primary">
                打开模型与服务商
              </Link>
            </div>
          </div>
        </SectionCard>

        <SectionCard title="运行默认值" subtitle="Gateway 与工作区">
          <div className="workbench-list">
            <article className="priority-card">
              <h3>Gateway</h3>
              <p>
                端口 {config.gateway.port} · 绑定 {config.gateway.bind} · 模式 {config.gateway.mode}
              </p>
            </article>
            <article className="priority-card">
              <h3>认证方式</h3>
              <p>{config.gateway.auth.mode}{config.gateway.auth.token ? " · 已配置 Token" : " · 未配置 Token"}</p>
            </article>
            <article className="priority-card">
              <h3>默认工作区</h3>
              <p>{config.agents.defaults.workspace}</p>
            </article>
            <article className="priority-card">
              <h3>配置文件</h3>
              <p>{path.join(OPENCLAW_ROOT, "openclaw.json")}</p>
            </article>
          </div>
        </SectionCard>

        <SectionCard title="服务商与接入" subtitle="低频配置汇总">
          <div className="workbench-list">
            <article className="priority-card">
              <h3>模型服务商</h3>
              <p>{providerNames.length} 个已配置：{providerNames.join("、")}</p>
            </article>
            <article className="priority-card">
              <h3>已启用渠道</h3>
              <p>{enabledChannels.length > 0 ? enabledChannels.join("、") : "当前没有启用渠道"}</p>
            </article>
            <article className="priority-card">
              <h3>允许插件</h3>
              <p>{config.plugins.allow?.length ? config.plugins.allow.join("、") : "未显式配置允许列表"}</p>
            </article>
          </div>
        </SectionCard>
      </div>
    </AppShell>
  );
}
