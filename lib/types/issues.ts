export const ISSUE_SOURCES = ["Cron", "Channel", "Agent", "Config"] as const;

export type IssueSource = (typeof ISSUE_SOURCES)[number];

export const ROOT_CAUSE_TYPES = [
  "channel_disabled",
  "plugin_disabled",
  "plugin_missing",
  "channel_plugin_mismatch",
  "credential_missing",
  "unsafe_policy",
  "primary_model_missing",
  "primary_model_unavailable",
  "gateway_unreachable",
  "gateway_restart_required",
  "agent_dispatch_failure",
  "session_log_error_detected",
] as const;

export type RootCauseType = (typeof ROOT_CAUSE_TYPES)[number];

export const REPAIRABILITIES = ["auto", "confirm", "manual"] as const;

export type Repairability = (typeof REPAIRABILITIES)[number];

export const VERIFICATION_STATUSES = ["resolved", "partially_resolved", "unresolved"] as const;

export type VerificationStatus = (typeof VERIFICATION_STATUSES)[number];

export type IssueEvidence = {
  summary: string;
  detail: string;
  impactScope: string;
};

export type RepairAction = {
  kind: "enable_channel" | "enable_plugin" | "switch_model" | "restart_gateway" | "rerun_job" | "fix_target";
  label: string;
  description?: string;
};

export type RepairPlan = {
  repairability: Repairability;
  summary: string;
  steps: string[];
  actions: RepairAction[];
  fallbackManualSteps: string[];
};

export type VerificationResult = {
  status: VerificationStatus;
  summary: string;
};

export type IssueRootCause = {
  type: RootCauseType;
  evidence: IssueEvidence;
};

export type RootCauseAssessment = {
  type: RootCauseType;
  severity: "medium" | "high";
  summary: string;
  details: string;
  impactScope: string;
  evidence: IssueEvidence;
};

export type Issue = {
  id: string;
  source: IssueSource;
  title: string;
  summary: string;
  severity: "medium" | "high";
  rootCause: IssueRootCause;
  repairPlan: RepairPlan;
  verificationStatus: VerificationStatus;
};
