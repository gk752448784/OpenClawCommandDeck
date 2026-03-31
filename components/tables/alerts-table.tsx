import type { AlertModel } from "@/lib/types/view-models";
import { FixCronTargetForm } from "@/components/control/fix-cron-target-form";

export function AlertsTable({ alerts }: { alerts: AlertModel[] }) {
  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>标题</th>
          <th>分类</th>
          <th>等级</th>
          <th>建议动作</th>
          <th>处理</th>
        </tr>
      </thead>
      <tbody>
        {alerts.map((alert) => (
          <tr key={alert.id}>
            <td>{alert.title}</td>
            <td>{alert.category}</td>
            <td>{alert.severity}</td>
            <td>{alert.recommendedAction}</td>
            <td>
              {alert.category === "Cron" ? (
                <FixCronTargetForm cronId={alert.targetId} />
              ) : (
                "-"
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
