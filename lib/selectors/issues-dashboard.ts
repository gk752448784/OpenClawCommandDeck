import type { Issue, Repairability, VerificationStatus } from "@/lib/types/issues";

export type IssuesDashboardModel = {
  summary: {
    total: number;
    high: number;
    medium: number;
    autoRepairable: number;
  };
  items: Array<
    Issue & {
      primaryAction: string;
      repairabilityLabel: string;
      verificationLabel: string;
    }
  >;
};

function repairabilityLabel(repairability: Repairability) {
  switch (repairability) {
    case "auto":
      return "可自动修复";
    case "confirm":
      return "修复需确认";
    default:
      return "人工处理";
  }
}

function verificationLabel(status: VerificationStatus) {
  switch (status) {
    case "resolved":
      return "已恢复";
    case "partially_resolved":
      return "部分恢复";
    default:
      return "待验证";
  }
}

function primaryAction(issue: Issue) {
  switch (issue.repairPlan.repairability) {
    case "auto":
      return "立即修复";
    case "confirm":
      return "确认后修复";
    default:
      return "查看人工步骤";
  }
}

export function buildIssuesDashboardModel(issues: Issue[]): IssuesDashboardModel {
  const items = [...issues]
    .sort((left, right) => {
      if (left.severity !== right.severity) {
        return left.severity === "high" ? -1 : 1;
      }

      if (left.repairPlan.repairability !== right.repairPlan.repairability) {
        const rank = {
          auto: 0,
          confirm: 1,
          manual: 2
        } as const;

        return rank[left.repairPlan.repairability] - rank[right.repairPlan.repairability];
      }

      return left.title.localeCompare(right.title, "zh-CN");
    })
    .map((issue) => ({
      ...issue,
      primaryAction: primaryAction(issue),
      repairabilityLabel: repairabilityLabel(issue.repairPlan.repairability),
      verificationLabel: verificationLabel(issue.verificationStatus)
    }));

  return {
    summary: {
      total: issues.length,
      high: issues.filter((issue) => issue.severity === "high").length,
      medium: issues.filter((issue) => issue.severity === "medium").length,
      autoRepairable: issues.filter((issue) => issue.repairPlan.repairability === "auto").length
    },
    items
  };
}
