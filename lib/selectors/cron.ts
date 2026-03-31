import type { CronJobs } from "@/lib/validators/cron-jobs";

export function summarizeCron(cron: CronJobs) {
  const failedCount = cron.jobs.filter(
    (job) => job.state.lastStatus === "error" || job.state.lastRunStatus === "error"
  ).length;

  return {
    total: cron.jobs.length,
    failedCount
  };
}
