import { describe, expect, it } from "vitest";

import { buildDiagnosticsModel } from "@/lib/selectors/diagnostics";

describe("diagnostics selector", () => {
  it("maps status and logs into a diagnosis view model", () => {
    const model = buildDiagnosticsModel({
      status: {
        runtimeVersion: "2026.3.13",
        gateway: {
          reachable: false,
          error: "missing scope: operator.read"
        },
        securityAudit: {
          summary: {
            critical: 3,
            warn: 5,
            info: 1
          },
          findings: [
            {
              checkId: "security.exposure.open_groups_with_elevated",
              severity: "critical",
              title: "Open groupPolicy with elevated tools enabled",
              detail: "Prompt injection risk",
              remediation: "Set groupPolicy to allowlist"
            }
          ]
        }
      },
      issues: [
        {
          id: "config:gateway_unreachable:gateway",
          source: "Config",
          title: "Gateway 当前不可达",
          summary: "模型侧诊断无法连接 gateway。",
          severity: "high",
          rootCause: {
            type: "gateway_unreachable",
            evidence: {
              summary: "connect ECONNREFUSED",
              detail: "status command failed",
              impactScope: "gateway"
            }
          },
          repairPlan: {
            repairability: "confirm",
            summary: "确认后重启 gateway。",
            steps: ["执行 gateway restart"],
            actions: [{ kind: "restart_gateway", label: "重启 gateway" }],
            fallbackManualSteps: ["手动执行 gateway restart"]
          },
          verificationStatus: "unresolved"
        }
      ],
      logs: [
        "2026-03-26T03:13:03.415Z info gateway/ws missing scope",
        "2026-03-26T03:13:03.419Z info gateway/ws config.get failed"
      ]
    });

    expect(model.runtimeVersion).toBe("2026.3.13");
    expect(model.gateway.status).toBe("warning");
    expect(model.security.critical).toBe(3);
    expect(model.findings[0]?.remediation).toContain("allowlist");
    expect(model.issueEvidence[0]?.title).toBe("Gateway 当前不可达");
    expect(model.logs).toHaveLength(2);
  });
});
