import { describe, expect, it } from "vitest";

import { buildAgentsDashboardModel } from "@/lib/selectors/agents-dashboard";
import type { AgentDefinition } from "@/lib/adapters/agents";

const agents: AgentDefinition[] = [
  {
    id: "main",
    name: "main",
    workspace: "/home/cloud/.openclaw/workspace",
    agentDir: "/home/cloud/.openclaw/agents/main/agent",
    role: "main",
    identity: "# IDENTITY\n\n- **Vibe:** Helpful, concise, execution-oriented."
  },
  {
    id: "chief-of-staff",
    name: "chief-of-staff",
    workspace: "/home/cloud/.openclaw/executive-feishu-suite/agents/chief-of-staff",
    agentDir: "/home/cloud/.openclaw/agents/chief-of-staff/agent",
    role: "chief-of-staff",
    identity: "你是总经理的效率管家，负责让工作日顺畅运转。"
  },
  {
    id: "second-brain",
    name: "second-brain",
    workspace: "/home/cloud/.openclaw/executive-feishu-suite/agents/second-brain",
    agentDir: "/home/cloud/.openclaw/agents/second-brain/agent",
    role: "second-brain",
    identity: "你是总经理的第二大脑和知识雷达。"
  }
];

describe("agents dashboard selector", () => {
  it("maps agent definitions into role-first cards", () => {
    const model = buildAgentsDashboardModel(agents);

    expect(model.summary.total).toBe(3);
    expect(model.summary.roles).toEqual(["执行系统", "知识雷达", "主助手"]);
    expect(model.items[0]).toMatchObject({
      id: "chief-of-staff",
      title: "执行系统",
      badge: "效率管家"
    });
    expect(model.items[0]?.summary).toContain("顺畅运转");
    expect(model.items[1]).toMatchObject({
      id: "second-brain",
      title: "知识雷达"
    });
    expect(model.items[2]?.workspaceName).toBe("workspace");
  });
});
