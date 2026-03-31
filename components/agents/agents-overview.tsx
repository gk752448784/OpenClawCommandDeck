import type { AgentDefinition } from "@/lib/adapters/agents";

import { AgentDispatchForm } from "@/components/control/agent-dispatch-form";
import { buildAgentsDashboardModel } from "@/lib/selectors/agents-dashboard";

function agentLabel(id: string, title: string) {
  if (id === "chief-of-staff") {
    return "效率管家";
  }
  if (id === "second-brain") {
    return "知识管家";
  }
  return title;
}

export function AgentsOverview({
  agents,
  issueCountsByAgent = {}
}: {
  agents: AgentDefinition[];
  issueCountsByAgent?: Record<string, number>;
}) {
  const model = buildAgentsDashboardModel(agents);
  const dispatchAgents = model.items.map((item) => ({
    id: item.id,
    label: agentLabel(item.id, item.title)
  }));

  return (
    <div className="management-layout">
      <section className="management-metrics management-metrics-compact management-metrics-compact-2">
        <div className="metric-card">
          <span className="metric-label">代理数量</span>
          <strong className="metric-value">{model.summary.total}</strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">角色覆盖</span>
          <strong className="metric-value">{model.summary.roles.length}</strong>
        </div>
      </section>

      <section className="management-card-grid">
        {model.items.map((item) => (
          <article key={item.id} className="management-card">
            <div className="management-card-top">
              <div>
                <div className="management-card-meta">
                  <span>{item.badge}</span>
                  <span>{item.workspaceName}</span>
                </div>
                <h3>{item.title}</h3>
              </div>
              <span className="status-badge status-healthy">
                <span className="status-dot" />
                可用
              </span>
            </div>

            <p className="management-card-summary">{item.summary}</p>

            <div className="management-tags">
              <span className="management-tag">工作区：{item.workspaceName}</span>
              <span className="management-tag">{item.id}</span>
              <span className="management-tag">问题线索：{issueCountsByAgent[item.id] ?? 0}</span>
            </div>

            <AgentDispatchForm
              agents={dispatchAgents}
              initialAgentId={item.id}
              title="派发给该代理"
              placeholder={item.suggestedPrompt}
              showAgentSelect={false}
              submitLabel="发送任务"
              compact
            />
          </article>
        ))}
      </section>
    </div>
  );
}
