import type { RootCauseAssessment } from "@/lib/types/issues";
import type { LogSignals } from "@/lib/signals/logs";

const ERROR_RE = /\berror\b|\bfail(?:ed|ure)?\b|\btimeout\b/i;

export function classifyLogRootCauses(signals: LogSignals): RootCauseAssessment[] {
  const rootCauses: RootCauseAssessment[] = [];

  for (const reference of signals.references) {
    const line = signals.excerpts[reference.lineIndex];
    if (!line) {
      continue;
    }

    if (/\bgateway restart required\b/i.test(line)) {
      rootCauses.push({
        type: "gateway_restart_required",
        severity: "high",
        summary: "日志显示 gateway 需要重启以恢复服务",
        details: line,
        impactScope: "gateway",
        evidence: {
          summary: "gateway restart required",
          detail: line,
          impactScope: "gateway"
        }
      });
    }

    if (!ERROR_RE.test(line)) {
      continue;
    }

    const impactScope = reference.sessionKey ?? reference.sessionId ?? reference.agentId ?? "logs";

    rootCauses.push({
      type: "session_log_error_detected",
      severity: "high",
      summary: "会话日志中检测到显式错误信号",
      details: line,
      impactScope,
      evidence: {
        summary: "日志包含 error/failure/timeout 关键词",
        detail: line,
        impactScope
      }
    });

    if (/\bdispatch\b/i.test(line)) {
      rootCauses.push({
        type: "agent_dispatch_failure",
        severity: "high",
        summary: "代理派发日志中检测到失败信号",
        details: line,
        impactScope,
        evidence: {
          summary: "dispatch 相关日志包含 error/failure/timeout",
          detail: line,
          impactScope
        }
      });
    }

    break;
  }

  return rootCauses;
}
