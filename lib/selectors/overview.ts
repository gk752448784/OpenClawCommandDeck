import type { AgentDefinition } from "@/lib/adapters/agents";
import type { OpenClawConfig } from "@/lib/validators/openclaw-config";
import type { CronJobs } from "@/lib/validators/cron-jobs";
import type { OverviewModel, RoleCard, SuggestionItem } from "@/lib/types/view-models";
import { buildAlertsModel } from "@/lib/selectors/alerts";
import { buildChannelsSummary } from "@/lib/selectors/channels";
import { summarizeCron } from "@/lib/selectors/cron";
import { summarizeAgents } from "@/lib/selectors/agents";

function buildRoleCards(agents: AgentDefinition[], cron: CronJobs): RoleCard[] {
  return agents.map((agent) => {
    if (agent.role === "chief-of-staff") {
      return {
        id: agent.id,
        title: "执行系统",
        summary: "盯住近 24/72 小时的推进节奏、阻塞项和缺口。",
        metrics: [
          { label: "角色", value: "效率管家" },
          { label: "职责", value: "执行与跟进" }
        ]
      };
    }

    if (agent.role === "second-brain") {
      return {
        id: agent.id,
        title: "知识雷达",
        summary: "聚合高信号信息、碎片归档和跨主题关联。",
        metrics: [
          { label: "角色", value: "知识管家" },
          { label: "职责", value: "知识与雷达" }
        ]
      };
    }

    return {
      id: agent.id,
      title: "主助手",
      summary: "管理主工作区、主动任务和全局上下文。",
      metrics: [
        { label: "工作区", value: agent.workspace.split("/").slice(-1)[0] ?? "workspace" },
        { label: "计划任务", value: String(cron.jobs.filter((job) => job.agentId === agent.id).length) }
      ]
    };
  });
}

function buildSuggestions(alertCount: number): SuggestionItem[] {
  return [
    {
      id: "chief-of-staff-1",
      source: "chief-of-staff",
      title: "先修复失败的计划任务",
      summary:
        alertCount > 0
          ? "存在需要人工处理的失败任务，优先补齐投递目标再恢复节奏。"
          : "当前没有失败任务，可继续关注今日执行节奏。"
    },
    {
      id: "second-brain-1",
      source: "second-brain",
      title: "整理今日知识沉淀",
      summary: "结合深夜复盘任务，把值得保留的内容推进到 knowledge 目录。"
    }
  ];
}

export function buildOverviewModel({
  config,
  cron,
  heartbeat,
  agents
}: {
  config: OpenClawConfig;
  cron: CronJobs;
  heartbeat: string;
  agents: AgentDefinition[];
}): OverviewModel {
  const alerts = buildAlertsModel({ cron });
  const channelSummary = buildChannelsSummary(config);
  const cronSummary = summarizeCron(cron);
  const agentSummary = summarizeAgents(agents);
  const healthyChannels = channelSummary.filter((channel) => channel.health === "healthy").length;
  const enabledChannels = channelSummary.filter((channel) => channel.enabled).length;
  const statusSummary =
    alerts.length > 0
      ? `系统整体需要关注，当前有 ${alerts.length} 个告警、${cronSummary.failedCount} 个计划任务失败。首页优先告诉你哪里阻塞、哪里漂移、下一步该进哪个模块处理。`
      : `系统整体稳定，当前 ${healthyChannels} 个渠道状态正常，计划任务运行平稳。这里先回答“现在 OpenClaw 是否健康”，再把关键入口收拢到同一屏。`;

  return {
    topBar: {
      appName: "OpenClaw 控制中心",
      health: alerts.length > 0 ? "warning" : "healthy",
      timezone: "Asia/Shanghai",
      instanceLabel: "本地运行与协作面板",
      statusSummary,
      channelSummary: {
        online: enabledChannels,
        total: channelSummary.length
      },
      agentSummary: {
        active: agentSummary.activeCount,
        total: agentSummary.totalCount
      },
      alertsToday: alerts.length,
      primaryModel: config.agents.defaults.model.primary,
      quickActions: [
        { href: "/alerts", label: "告警中心" },
        { href: "/control", label: "运行控制" },
        { href: "/channels", label: "消息渠道" },
        { href: "/settings", label: "设置中心" }
      ]
    },
    priorityCards: alerts.map((alert) => ({
      id: alert.id,
      title: alert.title,
      type: "计划任务失败",
      source: "main",
      summary: alert.summary,
      recommendedAction: alert.recommendedAction,
      severity: alert.severity
    })),
    todayTimeline: cron.jobs.map((job) => ({
      id: job.id,
      label: job.name,
      schedule: `${job.schedule.expr} (${job.schedule.tz})`,
      type: job.schedule.kind
    })),
    suggestions: buildSuggestions(alerts.length),
    roleCards: buildRoleCards(agents, cron),
    rightRail: {
      channels: {
        healthyCount: channelSummary.filter((channel) => channel.health === "healthy").length,
        totalCount: channelSummary.length
      },
      agents: {
        activeCount: agentSummary.activeCount,
        totalCount: agentSummary.totalCount
      },
      cron: cronSummary,
      heartbeat: {
        enabled: heartbeat.includes("HEARTBEAT_OK"),
        notes: heartbeat
          .split("\n")
          .filter((line) => line.trim().startsWith("- "))
          .slice(0, 3)
      }
    }
  };
}
