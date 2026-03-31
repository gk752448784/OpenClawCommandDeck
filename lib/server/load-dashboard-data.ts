import path from "node:path";

import { OPENCLAW_ROOT } from "@/lib/config";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { loadHeartbeatGuide } from "@/lib/adapters/heartbeat";
import { loadAgentDefinitions } from "@/lib/adapters/agents";
import { loadSessionsSnapshot } from "@/lib/adapters/sessions";
import { buildOverviewModel } from "@/lib/selectors/overview";
import { buildAlertsModel } from "@/lib/selectors/alerts";
import { buildChannelsSummary } from "@/lib/selectors/channels";
import { summarizeCron } from "@/lib/selectors/cron";
import { summarizeAgents } from "@/lib/selectors/agents";
import { buildSessionsModel } from "@/lib/selectors/sessions";
import { buildDiagnosticsModel } from "@/lib/selectors/diagnostics";
import {
  parseOpenClawJsonOutput,
  runOpenClawCli,
  summarizeLogLines,
  tryRunOpenClawCli
} from "@/lib/server/openclaw-cli";

const DIAGNOSTICS_TTL_MS = 15_000;

let diagnosticsCache:
  | {
      expiresAt: number;
      data: ReturnType<typeof buildDiagnosticsModel>;
    }
  | undefined;

async function requireOk<T>(
  result: Promise<
    | {
        ok: true;
        data: T;
      }
    | {
        ok: false;
        error: {
          code: string;
          message: string;
        };
      }
  >
): Promise<T> {
  const resolved = await result;
  if (!resolved.ok) {
    throw new Error(`${resolved.error.code}: ${resolved.error.message}`);
  }
  return resolved.data;
}

export async function loadCoreDashboardData() {
  const config = await requireOk(loadOpenClawConfig(path.join(OPENCLAW_ROOT, "openclaw.json")));
  const cron = await requireOk(loadCronJobs(path.join(OPENCLAW_ROOT, "cron/jobs.json")));
  const heartbeat = await requireOk(
    loadHeartbeatGuide(path.join(OPENCLAW_ROOT, "workspace/HEARTBEAT.md"))
  );
  const agents = await requireOk(loadAgentDefinitions(OPENCLAW_ROOT));

  return {
    overview: buildOverviewModel({
      config,
      cron,
      heartbeat,
      agents
    }),
    alerts: buildAlertsModel({ cron }),
    channels: buildChannelsSummary(config),
    cronSummary: summarizeCron(cron),
    agentsSummary: summarizeAgents(agents),
    agents,
    config,
    cron
  };
}

export async function loadDashboardData() {
  const core = await loadCoreDashboardData();
  const sessionsResult = await requireOk(
    loadSessionsSnapshot(
      OPENCLAW_ROOT,
      core.agents.map((agent) => agent.id)
    )
  );
  const diagnostics = await loadDiagnosticsData();

  return {
    ...core,
    sessions: buildSessionsModel(sessionsResult),
    diagnostics
  };
}

export async function loadDiagnosticsData() {
  if (diagnosticsCache && diagnosticsCache.expiresAt > Date.now()) {
    return diagnosticsCache.data;
  }

  const [statusOutput, logsOutput] = await Promise.all([
    runOpenClawCli(["status", "--json"]),
    tryRunOpenClawCli(["logs", "--plain", "--limit", "30"])
  ]);
  const status = parseOpenClawJsonOutput<{
    runtimeVersion: string;
    gateway?: {
      reachable?: boolean;
      error?: string | null;
    };
    securityAudit?: {
      summary?: {
        critical?: number;
        warn?: number;
        info?: number;
      };
      findings?: Array<{
        checkId: string;
        severity: "critical" | "warn" | "info";
        title: string;
        detail: string;
        remediation?: string;
      }>;
    };
  }>(statusOutput.stdout);
  const logs = summarizeLogLines(`${logsOutput.stdout}\n${logsOutput.stderr}`);
  const diagnostics = buildDiagnosticsModel({
    status,
    logs
  });

  diagnosticsCache = {
    data: diagnostics,
    expiresAt: Date.now() + DIAGNOSTICS_TTL_MS
  };

  return diagnostics;
}
