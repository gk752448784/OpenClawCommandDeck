import path from "node:path";

import { AppShell } from "@/components/layout/app-shell";
import { ActionButton } from "@/components/control/action-button";
import { AgentDispatchForm } from "@/components/control/agent-dispatch-form";
import { ModelSwitchForm } from "@/components/control/model-switch-form";
import { FixCronTargetForm } from "@/components/control/fix-cron-target-form";
import { RecentActionsPanel } from "@/components/control/recent-actions-panel";
import { loadCoreDashboardData } from "@/lib/server/load-dashboard-data";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { OPENCLAW_ROOT } from "@/lib/config";

export default async function ControlPage() {
  const data = await loadCoreDashboardData();
  const configResult = await loadOpenClawConfig(path.join(OPENCLAW_ROOT, "openclaw.json"));
  const cronResult = await loadCronJobs(path.join(OPENCLAW_ROOT, "cron/jobs.json"));

  if (!configResult.ok || !cronResult.ok) {
    throw new Error("无法加载控制台需要的实时数据");
  }

  const availableModels = Object.keys(configResult.data.agents.defaults.models);
  const failedTargetJob = cronResult.data.jobs.find((job) =>
    job.state.lastError?.includes("requires target")
  );
  const quickActionJob =
    cronResult.data.jobs.find(
      (job) => job.name === "daily-review" || job.description?.includes("复盘")
    ) ?? cronResult.data.jobs[0];

  return (
    <AppShell
      topBar={data.overview.topBar}
      topBarVariant="compact"
      pageTitle="行动区"
      pageSubtitle="高频动作与最近留痕"
    >
      <div className="control-grid">
        <section className="control-zone control-zone-quick-actions control-zone-primary">
          <header className="control-zone-header">
            <div>
              <p className="eyebrow">立即动作</p>
              <h2>运行控制</h2>
              <p>常用动作优先展示，减少切换成本。</p>
            </div>
          </header>
          <div className="quick-actions">
            {quickActionJob ? (
              <>
                <ActionButton
                  action="run-cron"
                  payload={{ id: quickActionJob.id }}
                  label="立即执行复盘"
                />
                <ActionButton
                  action="toggle-cron"
                  payload={{ id: quickActionJob.id, enabled: false }}
                  label="停用每日复盘"
                  variant="secondary"
                  confirmMessage="确认停用“每日复盘”吗？"
                />
                <ActionButton
                  action="toggle-channel"
                  payload={{ channelId: "feishu", enabled: false }}
                  label="停用飞书渠道"
                  variant="secondary"
                  confirmMessage="确认停用飞书渠道吗？这会影响主入口消息收发。"
                />
              </>
            ) : null}
          </div>
        </section>

        <section className="control-zone control-zone-secondary control-zone-jobs">
          <header className="control-zone-header">
            <div>
              <p className="eyebrow">计划任务</p>
              <h2>定时任务控制</h2>
              <p>启停、重跑和修复都集中在这里。</p>
            </div>
          </header>
          <div className="control-stack">
            {cronResult.data.jobs.map((job) => (
              <div key={job.id} className="control-row">
                <div>
                  <strong>{job.description ?? job.name}</strong>
                  <p>{job.schedule.expr}</p>
                </div>
                <div className="inline-actions">
                  <ActionButton
                    action="toggle-cron"
                    payload={{ id: job.id, enabled: !job.enabled }}
                    label={job.enabled ? "停用" : "启用"}
                    variant="secondary"
                    confirmMessage={
                      job.enabled
                        ? `确认停用“${job.description ?? job.name}”吗？`
                        : `确认启用“${job.description ?? job.name}”吗？`
                    }
                  />
                  <ActionButton
                    action="run-cron"
                    payload={{ id: job.id }}
                    label="立即执行"
                  />
                </div>
              </div>
            ))}
            {failedTargetJob ? (
              <FixCronTargetForm cronId={failedTargetJob.id} />
            ) : null}
          </div>
        </section>

        <section className="control-zone control-zone-secondary control-zone-dispatch">
          <header className="control-zone-header">
            <div>
              <p className="eyebrow">任务流</p>
              <h2>任务派发与模型切换</h2>
              <p>派发、模型切换和代理分工放在同一块区域。</p>
            </div>
          </header>
          <div className="control-stack">
            <ModelSwitchForm
              currentModel={configResult.data.agents.defaults.model.primary}
              models={availableModels}
            />
            <AgentDispatchForm
              agents={data.agents.map((agent) => ({
                id: agent.id,
                label:
                  agent.role === "chief-of-staff"
                    ? "效率管家"
                    : agent.role === "second-brain"
                      ? "知识管家"
                      : "主助手"
              }))}
            />
          </div>
        </section>

        <RecentActionsPanel />
      </div>
    </AppShell>
  );
}
