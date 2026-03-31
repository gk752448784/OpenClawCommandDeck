import type { CronJobs } from "@/lib/validators/cron-jobs";
import { ActionButton } from "@/components/control/action-button";
import { FixCronTargetForm } from "@/components/control/fix-cron-target-form";

export function CronTable({ cron }: { cron: CronJobs }) {
  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>任务名</th>
          <th>代理</th>
          <th>调度</th>
          <th>状态</th>
          <th>最近错误</th>
          <th>操作</th>
        </tr>
      </thead>
      <tbody>
        {cron.jobs.map((job) => (
          <tr key={job.id}>
            <td>{job.name}</td>
            <td>{job.agentId}</td>
            <td>{job.schedule.expr}</td>
            <td>{job.state.lastStatus === "error" ? "失败" : job.state.lastStatus ?? "未知"}</td>
            <td>{job.state.lastError ?? "-"}</td>
            <td className="table-actions">
              <ActionButton
                action="toggle-cron"
                payload={{ id: job.id, enabled: !job.enabled }}
                label={job.enabled ? "停用" : "启用"}
                variant="secondary"
              />
              <ActionButton
                action="run-cron"
                payload={{ id: job.id }}
                label="立即执行"
              />
              {job.state.lastError?.includes("requires target") ? (
                <FixCronTargetForm cronId={job.id} />
              ) : null}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
