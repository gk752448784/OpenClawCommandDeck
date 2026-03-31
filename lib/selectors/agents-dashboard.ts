import type { AgentDefinition } from "@/lib/adapters/agents";

export type AgentDashboardItem = {
  id: string;
  title: string;
  badge: string;
  summary: string;
  workspaceName: string;
  workspace: string;
  suggestedPrompt: string;
};

export type AgentsDashboardModel = {
  summary: {
    total: number;
    roles: string[];
  };
  items: AgentDashboardItem[];
};

function extractSummary(agent: AgentDefinition) {
  if (agent.role === "chief-of-staff") {
    return {
      title: "执行系统",
      badge: "效率管家",
      summary:
        agent.identity?.split("\n").find((line) => line.trim().length > 0) ??
        "负责推进日程、跟进和执行节奏。",
      suggestedPrompt: "整理今天的待办、阻塞项和下一步动作"
    };
  }

  if (agent.role === "second-brain") {
    return {
      title: "知识雷达",
      badge: "知识管家",
      summary:
        agent.identity?.split("\n").find((line) => line.trim().length > 0) ??
        "负责信息雷达、知识归档和长期沉淀。",
      suggestedPrompt: "整理今天值得存档的输入，并给出知识沉淀建议"
    };
  }

  return {
    title: "主助手",
    badge: "总控中枢",
    summary:
      agent.identity?.split("\n").find((line) => line.includes("Vibe")) ??
      "负责主工作区、跨模块协同和总体执行。",
    suggestedPrompt: "汇总今天最重要的事项，并给出下一步建议"
  };
}

export function buildAgentsDashboardModel(
  agents: AgentDefinition[]
): AgentsDashboardModel {
  const items = [...agents]
    .sort((left, right) => {
      const order = {
        "chief-of-staff": 0,
        "second-brain": 1,
        main: 2,
        custom: 3
      } as const;
      return order[left.role] - order[right.role];
    })
    .map((agent) => {
      const summary = extractSummary(agent);

      return {
        id: agent.id,
        title: summary.title,
        badge: summary.badge,
        summary: summary.summary.replace(/^[-*#\s]+/, ""),
        workspaceName: agent.workspace.split("/").slice(-1)[0] ?? agent.workspace,
        workspace: agent.workspace,
        suggestedPrompt: summary.suggestedPrompt
      };
    });

  return {
    summary: {
      total: agents.length,
      roles: items.map((item) => item.title)
    },
    items
  };
}
