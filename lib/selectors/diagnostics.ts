import type { DiagnosticsModel } from "@/lib/types/view-models";

type RawFinding = {
  checkId: string;
  severity: "critical" | "warn" | "info";
  title: string;
  detail: string;
  remediation?: string;
};

type RawDiagnosticsStatus = {
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
    findings?: RawFinding[];
  };
};

export function buildDiagnosticsModel({
  status,
  logs
}: {
  status: RawDiagnosticsStatus;
  logs: string[];
}): DiagnosticsModel {
  const gatewayReachable = status.gateway?.reachable ?? false;
  const gatewayError = status.gateway?.error ?? "";

  return {
    runtimeVersion: status.runtimeVersion,
    gateway: {
      status: gatewayReachable ? "healthy" : gatewayError ? "warning" : "critical",
      summary: gatewayReachable ? "Gateway 可访问" : "Gateway 访问受限",
      detail: gatewayError || "当前没有拿到可用的 Gateway 健康响应。"
    },
    security: {
      critical: status.securityAudit?.summary?.critical ?? 0,
      warn: status.securityAudit?.summary?.warn ?? 0,
      info: status.securityAudit?.summary?.info ?? 0
    },
    logs: logs.slice(0, 12),
    findings: (status.securityAudit?.findings ?? []).slice(0, 6).map((finding) => ({
      id: finding.checkId,
      severity: finding.severity,
      title: finding.title,
      detail: finding.detail,
      remediation: finding.remediation
    }))
  };
}
