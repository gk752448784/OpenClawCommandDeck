import path from "node:path";

import { safeReadTextFile } from "@/lib/server/safe-read";
import type { LoadResult } from "@/lib/types/raw";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";

export type AgentRole = "main" | "chief-of-staff" | "second-brain" | "custom";

export type AgentDefinition = {
  id: string;
  name: string;
  workspace: string;
  agentDir: string;
  role: AgentRole;
  identity?: string;
};

function inferAgentRole(agentId: string): AgentRole {
  if (agentId === "main") {
    return "main";
  }
  if (agentId === "chief-of-staff") {
    return "chief-of-staff";
  }
  if (agentId === "second-brain") {
    return "second-brain";
  }
  return "custom";
}

export async function loadAgentDefinitions(
  openClawRoot: string
): Promise<LoadResult<AgentDefinition[]>> {
  const configResult = await loadOpenClawConfig(path.join(openClawRoot, "openclaw.json"));
  if (!configResult.ok) {
    return configResult;
  }

  const agents = await Promise.all(
    configResult.data.agents.list.map(async (agent) => {
      const identityResult = await safeReadTextFile(path.join(agent.workspace, "IDENTITY.md"));

      return {
        id: agent.id,
        name: agent.name ?? agent.id,
        workspace: agent.workspace,
        agentDir: agent.agentDir,
        role: inferAgentRole(agent.id),
        identity: identityResult.ok ? identityResult.data : undefined
      };
    })
  );

  return {
    ok: true,
    data: agents
  };
}
