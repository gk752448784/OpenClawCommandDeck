import type { AlertModel } from "@/lib/types/view-models";

export type AlertsDashboardModel = {
  summary: {
    total: number;
    high: number;
    medium: number;
  };
  items: Array<
    AlertModel & {
      primaryAction: string;
      needsRepair: boolean;
    }
  >;
};

export function buildAlertsDashboardModel(alerts: AlertModel[]): AlertsDashboardModel {
  const items = [...alerts]
    .sort((left, right) => {
      if (left.severity !== right.severity) {
        return left.severity === "high" ? -1 : 1;
      }
      return left.title.localeCompare(right.title, "zh-CN");
    })
    .map((alert) => ({
      ...alert,
      needsRepair: alert.needsRepair ?? false,
      primaryAction:
        alert.needsRepair
          ? "立即修复"
          : "查看建议"
    }));

  return {
    summary: {
      total: alerts.length,
      high: alerts.filter((alert) => alert.severity === "high").length,
      medium: alerts.filter((alert) => alert.severity === "medium").length
    },
    items
  };
}
