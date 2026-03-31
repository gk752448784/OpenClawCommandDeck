import type { AgentDefinition } from "@/lib/adapters/agents";

export function summarizeAgents(agents: AgentDefinition[]) {
  return {
    activeCount: agents.length,
    totalCount: agents.length
  };
}
