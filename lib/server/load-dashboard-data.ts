import path from "node:path";

import { OPENCLAW_ROOT } from "@/lib/config";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { loadCronJobs } from "@/lib/adapters/cron-jobs";
import { loadHeartbeatGuide } from "@/lib/adapters/heartbeat";
import { loadAgentDefinitions } from "@/lib/adapters/agents";
import { loadSessionsSnapshot, type SessionsSnapshot } from "@/lib/adapters/sessions";
import { collectChannelSignals, type ChannelSignal } from "@/lib/signals/channels";
import { collectGatewaySignal, type GatewaySignal } from "@/lib/signals/gateway";
import { collectLogSignals, type LogSignals } from "@/lib/signals/logs";
import { collectModelSignals, type ModelSignals } from "@/lib/signals/models";
import { buildOverviewModel } from "@/lib/selectors/overview";
import { buildAlertsModel } from "@/lib/selectors/alerts";
import { buildChannelsSummary } from "@/lib/selectors/channels";
import { summarizeCron } from "@/lib/selectors/cron";
import { summarizeAgents } from "@/lib/selectors/agents";
import { buildSessionsModel } from "@/lib/selectors/sessions";
import { buildDiagnosticsModel } from "@/lib/selectors/diagnostics";
import { buildIssues } from "@/lib/issues/build-issues";
import {
  parseOpenClawJsonOutput,
  summarizeLogLines,
  tryRunOpenClawCli
} from "@/lib/server/openclaw-cli";

const DIAGNOSTICS_TTL_MS = 15_000;

export type DiagnosticsStatusSignal = {
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
};

export type IssueSignals = {
  channels: ChannelSignal[];
  models: ModelSignals;
  gateway: GatewaySignal;
  logs: LogSignals;
};

type CoreDashboardData = Awaited<ReturnType<typeof loadCoreDashboardData>>;

let diagnosticsCache:
  | {
      expiresAt: number;
      data: ReturnType<typeof buildDiagnosticsModel>;
    }
  | undefined;
let diagnosticsSignalsCache:
  | {
      expiresAt: number;
      data: {
        status: DiagnosticsStatusSignal;
        logs: string[];
      };
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

function emptyDiagnosticsSignals(): {
  status: DiagnosticsStatusSignal;
  logs: string[];
} {
  return {
    status: {
      runtimeVersion: "unknown",
      gateway: {
        error: null
      }
    },
    logs: []
  };
}

export async function loadIssueSignals({
  core,
  sessions,
  includeDiagnostics = true,
  diagnosticsSignals
}: {
  core?: CoreDashboardData;
  sessions?: SessionsSnapshot;
  includeDiagnostics?: boolean;
  diagnosticsSignals?: {
    status: DiagnosticsStatusSignal;
    logs: string[];
  };
} = {}): Promise<IssueSignals> {
  const resolvedCore = core ?? await loadCoreDashboardData();
  const resolvedSessions = sessions ?? await requireOk(
    loadSessionsSnapshot(
      OPENCLAW_ROOT,
      resolvedCore.agents.map((agent) => agent.id)
    )
  );
  const diagnostics = includeDiagnostics
    ? diagnosticsSignals ?? await loadDiagnosticsSignalsCached()
    : emptyDiagnosticsSignals();

  return {
    channels: collectChannelSignals(resolvedCore.config),
    models: collectModelSignals({
      config: resolvedCore.config,
      sessions: resolvedSessions
    }),
    gateway: collectGatewaySignal(diagnostics.status),
    logs: collectLogSignals({
      logs: diagnostics.logs,
      sessions: resolvedSessions
    })
  };
}

export async function loadDiagnosticsSignals(): Promise<{
  status: DiagnosticsStatusSignal;
  logs: string[];
}> {
  const [statusOutput, logsOutput] = await Promise.all([
    tryRunOpenClawCli(["status", "--json"]),
    tryRunOpenClawCli(["logs", "--plain", "--limit", "30"])
  ]);
  let status: DiagnosticsStatusSignal;

  if (statusOutput.ok) {
    try {
      status = parseOpenClawJsonOutput<DiagnosticsStatusSignal>(statusOutput.stdout);
    } catch {
      status = {
        runtimeVersion: "unknown",
        gateway: {
          error: null
        }
      };
    }
  } else {
    status = {
      runtimeVersion: "unknown",
      gateway: {
        error: null
      }
    };
  }
  const logs = summarizeLogLines(`${logsOutput.stdout}\n${logsOutput.stderr}`);

  return {
    status,
    logs
  };
}

async function loadDiagnosticsSignalsCached() {
  if (diagnosticsSignalsCache && diagnosticsSignalsCache.expiresAt > Date.now()) {
    return diagnosticsSignalsCache.data;
  }

  const data = await loadDiagnosticsSignals();
  diagnosticsSignalsCache = {
    data,
    expiresAt: Date.now() + DIAGNOSTICS_TTL_MS
  };
  return data;
}

export async function loadDiagnosticsData() {
  if (diagnosticsCache && diagnosticsCache.expiresAt > Date.now()) {
    return diagnosticsCache.data;
  }

  const { status, logs } = await loadDiagnosticsSignalsCached();
  const issueSignals = await loadIssueSignals({
    diagnosticsSignals: {
      status,
      logs
    }
  });
  const diagnostics = buildDiagnosticsModel({
    status,
    logs,
    issues: buildIssues({ signals: issueSignals })
  });

  diagnosticsCache = {
    data: diagnostics,
    expiresAt: Date.now() + DIAGNOSTICS_TTL_MS
  };

  return diagnostics;
}
