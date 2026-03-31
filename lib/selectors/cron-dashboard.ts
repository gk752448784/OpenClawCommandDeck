import type { CronJobs } from "@/lib/validators/cron-jobs";

export type CronDashboardItem = {
  id: string;
  title: string;
  agentId: string;
  schedule: string;
  deliverySummary: string;
  statusLabel: string;
  statusTone: "healthy" | "warning";
  summary: string;
  enabled: boolean;
  needsRepair: boolean;
  primaryAction: string;
};

export type CronDashboardModel = {
  summary: {
    total: number;
    enabled: number;
    failed: number;
    needsRepair: number;
  };
  items: CronDashboardItem[];
};

function formatDelivery(mode: string, channel?: string) {
  if (mode === "none") {
    return "未配置";
  }

  const modeLabel =
    mode === "announce" ? "广播" : mode === "reply" ? "回复" : mode === "webhook" ? "Webhook" : mode;

  if (!channel) {
    return modeLabel;
  }

  const channelLabel = channel === "last" ? "最近目标" : channel;

  return `${modeLabel} · ${channelLabel}`;
}

function buildStatus(job: CronJobs["jobs"][number]) {
  if (job.state.lastStatus === "error" || job.state.lastRunStatus === "error") {
    return {
      label: "执行失败",
      tone: "warning" as const
    };
  }

  if (!job.enabled) {
    return {
      label: "已停用",
      tone: "warning" as const
    };
  }

  return {
    label: "运行正常",
    tone: "healthy" as const
  };
}

export function buildCronDashboardModel(cron: CronJobs): CronDashboardModel {
  const items = [...cron.jobs]
    .sort((left, right) => {
      const leftFailed =
        left.state.lastStatus === "error" || left.state.lastRunStatus === "error";
      const rightFailed =
        right.state.lastStatus === "error" || right.state.lastRunStatus === "error";

      if (leftFailed !== rightFailed) {
        return leftFailed ? -1 : 1;
      }

      return (right.state.nextRunAtMs ?? 0) - (left.state.nextRunAtMs ?? 0);
    })
    .map((job) => {
      const status = buildStatus(job);
      const needsRepair = job.state.lastError?.includes("requires target") ?? false;

      return {
        id: job.id,
        title: job.description ?? job.name,
        agentId: job.agentId,
        schedule: `${job.schedule.expr} · ${job.schedule.tz}`,
        deliverySummary: formatDelivery(job.delivery.mode, job.delivery.channel),
        statusLabel: status.label,
        statusTone: status.tone,
        summary: job.state.lastError ?? "最近一次执行正常，可继续按当前节奏运行。",
        enabled: job.enabled,
        needsRepair,
        primaryAction: needsRepair ? "修复投递" : "立即执行"
      };
    });

  return {
    summary: {
      total: cron.jobs.length,
      enabled: cron.jobs.filter((job) => job.enabled).length,
      failed: cron.jobs.filter(
        (job) => job.state.lastStatus === "error" || job.state.lastRunStatus === "error"
      ).length,
      needsRepair: cron.jobs.filter((job) =>
        job.state.lastError?.includes("requires target")
      ).length
    },
    items
  };
}
