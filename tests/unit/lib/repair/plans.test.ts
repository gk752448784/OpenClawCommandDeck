import { describe, expect, it } from "vitest";

import { buildRepairPlanForRootCause } from "@/lib/repair/plans";
import type { RootCauseAssessment } from "@/lib/types/issues";

function createRootCause(
  overrides: Partial<RootCauseAssessment> & Pick<RootCauseAssessment, "type">
): RootCauseAssessment {
  return {
    type: overrides.type,
    severity: overrides.severity ?? "high",
    summary: overrides.summary ?? "summary",
    details: overrides.details ?? "details",
    impactScope: overrides.impactScope ?? "scope",
    evidence: overrides.evidence ?? {
      summary: "summary",
      detail: "detail",
      impactScope: overrides.impactScope ?? "scope"
    }
  };
}

describe("repair plan registry", () => {
  it("marks low-risk fixes as auto", () => {
    const plan = buildRepairPlanForRootCause(
      createRootCause({
        type: "channel_disabled",
        impactScope: "discord"
      })
    );

    expect(plan).toMatchObject({
      repairability: "auto"
    });
    expect(plan.actions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: "enable_channel"
        })
      ])
    );
  });

  it("marks model switch and gateway restart as confirm", () => {
    const modelPlan = buildRepairPlanForRootCause(
      createRootCause({
        type: "primary_model_missing",
        impactScope: "openai/gpt-5.4"
      })
    );
    const gatewayPlan = buildRepairPlanForRootCause(
      createRootCause({
        type: "gateway_unreachable",
        impactScope: "gateway"
      })
    );

    expect(modelPlan.repairability).toBe("confirm");
    expect(modelPlan.actions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: "switch_model"
        })
      ])
    );

    expect(gatewayPlan.repairability).toBe("confirm");
    expect(gatewayPlan.actions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: "restart_gateway"
        })
      ])
    );
  });

  it("marks unsupported cases as manual", () => {
    const plan = buildRepairPlanForRootCause(
      createRootCause({
        type: "credential_missing",
        impactScope: "feishu"
      })
    );

    expect(plan).toMatchObject({
      repairability: "manual",
      actions: []
    });
    expect(plan.fallbackManualSteps.length).toBeGreaterThan(0);
  });
});
