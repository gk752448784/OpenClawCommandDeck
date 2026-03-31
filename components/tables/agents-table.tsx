import type { AgentDefinition } from "@/lib/adapters/agents";

export function AgentsTable({
  agents,
  issueCountsByAgent = {}
}: {
  agents: AgentDefinition[];
  issueCountsByAgent?: Record<string, number>;
}) {
  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>代理</th>
          <th>角色</th>
          <th>工作区</th>
          <th>问题线索</th>
        </tr>
      </thead>
      <tbody>
        {agents.map((agent) => (
          <tr key={agent.id}>
            <td>{agent.id}</td>
            <td>
              {agent.role === "main"
                ? "主助手"
                : agent.role === "chief-of-staff"
                  ? "执行系统"
                  : agent.role === "second-brain"
                    ? "知识雷达"
                    : "自定义"}
            </td>
            <td>{agent.workspace}</td>
            <td>{issueCountsByAgent[agent.id] ?? 0} 条</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
