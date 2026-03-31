import type { CronJobs } from "@/lib/validators/cron-jobs";
import type { AlertModel } from "@/lib/types/view-models";

function cronRecommendedAction(message?: string) {
  if (!message) {
    return "Inspect the failed job and retry it after confirming the delivery target.";
  }

  if (message.includes("requires target")) {
    return "补充 `delivery.to`，或者改成当前会话投递模式后再重试。";
  }

  return "查看任务详情，修正配置后重新执行。";
}

export function buildAlertsModel({
  cron
}: {
  cron: CronJobs;
}): AlertModel[] {
  return cron.jobs
    .filter((job) => job.state.lastStatus === "error" || job.state.lastRunStatus === "error")
    .map((job) => ({
      id: `cron-${job.id}`,
      sourceId: job.name,
      targetId: job.id,
      severity: (job.state.consecutiveErrors ?? 0) > 0 ? "high" : "medium",
      category: "Cron",
      title: `${job.description ?? job.name} 执行失败`,
      summary: job.state.lastError ?? "最近一次执行失败，等待人工检查。",
      recommendedAction: cronRecommendedAction(job.state.lastError),
      needsRepair: job.state.lastError?.includes("requires target") ?? false
    }));
}
