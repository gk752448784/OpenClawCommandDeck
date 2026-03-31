import type { IssueSource } from "@/lib/types/issues";

export type HealthState = "healthy" | "warning" | "critical";

export type PriorityCardType = "计划任务失败" | "计划任务提醒";

export type PriorityCardSource =
  | "main"
  | "cron"
  | "channel"
  | "channels"
  | "agent"
  | "agents"
  | "config"
  | "chief-of-staff"
  | "second-brain";

export type TopBarModel = {
  appName: string;
  health: HealthState;
  timezone: string;
  instanceLabel?: string;
  statusSummary: string;
  channelSummary: {
    online: number;
    total: number;
  };
  agentSummary: {
    active: number;
    total: number;
  };
  alertsToday: number;
  primaryModel: string;
  quickActions?: Array<{
    href: string;
    label: string;
  }>;
};

export type PriorityCard = {
  id: string;
  title: string;
  type: PriorityCardType;
  source: PriorityCardSource;
  summary: string;
  recommendedAction: string;
  severity: "medium" | "high";
};

export type TimelineItem = {
  id: string;
  label: string;
  schedule: string;
  type: string;
};

export type SuggestionItem = {
  id: string;
  source: string;
  title: string;
  summary: string;
};

export type RoleCard = {
  id: string;
  title: string;
  summary: string;
  metrics: Array<{
    label: string;
    value: string;
  }>;
};

export type RightRailModel = {
  channels: {
    healthyCount: number;
    totalCount: number;
  };
  agents: {
    activeCount: number;
    totalCount: number;
  };
  cron: {
    total: number;
    failedCount: number;
  };
  heartbeat: {
    enabled: boolean;
    notes: string[];
  };
};

export type OverviewModel = {
  topBar: TopBarModel;
  priorityCards: PriorityCard[];
  todayTimeline: TimelineItem[];
  suggestions: SuggestionItem[];
  roleCards: RoleCard[];
  rightRail: RightRailModel;
};

export type SessionItemModel = {
  id: string;
  agentId: string;
  channel: string;
  kind: string;
  model: string;
  ageLabel: string;
  percentUsed: string;
  status: "active" | "waiting";
};

export type SessionsModel = {
  total: number;
  activeSummary: string;
  items: SessionItemModel[];
};

export type DiagnosticsModel = {
  runtimeVersion: string;
  gateway: {
    status: "healthy" | "warning" | "critical";
    summary: string;
    detail: string;
  };
  security: {
    critical: number;
    warn: number;
    info: number;
  };
  logs: string[];
  issueEvidence: Array<{
    id: string;
    source: string;
    title: string;
    summary: string;
    verificationStatus: "resolved" | "partially_resolved" | "unresolved";
    repairability: "auto" | "confirm" | "manual";
  }>;
  findings: Array<{
    id: string;
    severity: "critical" | "warn" | "info";
    title: string;
    detail: string;
    remediation?: string;
  }>;
};

export type AlertModel = {
  id: string;
  sourceId: string;
  targetId: string;
  severity: "medium" | "high";
  category: IssueSource;
  title: string;
  summary: string;
  recommendedAction: string;
  needsRepair?: boolean;
};
