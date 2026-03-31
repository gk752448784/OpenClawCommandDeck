import type { RootCauseAssessment } from "@/lib/types/issues";
import type { GatewaySignal } from "@/lib/signals/gateway";
import type { ModelSignals } from "@/lib/signals/models";

export function classifyModelRootCauses({
  models,
  gateway
}: {
  models: ModelSignals;
  gateway: GatewaySignal;
}): RootCauseAssessment[] {
  const rootCauses: RootCauseAssessment[] = [];

  if (!models.candidateModelKeys.includes(models.primaryModelKey)) {
    rootCauses.push({
      type: "primary_model_missing",
      severity: "high",
      summary: `主模型 ${models.primaryModelKey} 不在候选列表中`,
      details: `当前主模型未出现在配置和会话汇总出的候选模型列表里。`,
      impactScope: models.primaryModelKey,
      evidence: {
        summary: `主模型缺失`,
        detail: `primaryModelKey=${models.primaryModelKey}; candidates=${models.candidateModelKeys.join(",")}`,
        impactScope: models.primaryModelKey
      }
    });
  }

  if (gateway.reachable === "unreachable") {
    rootCauses.push({
      type: "gateway_unreachable",
      severity: "high",
      summary: "Gateway 当前不可达",
      details: gateway.error ?? "Gateway reachability 检查返回不可达。",
      impactScope: "gateway",
      evidence: {
        summary: "Gateway reachability=unreachable",
        detail: gateway.error ?? "No gateway error detail",
        impactScope: "gateway"
      }
    });
  }

  return rootCauses;
}
