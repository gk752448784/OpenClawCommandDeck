import { describe, expect, it } from "vitest";

import { buildIssues } from "@/lib/issues/build-issues";
import { REPAIRABILITIES, ROOT_CAUSE_TYPES, VERIFICATION_STATUSES } from "@/lib/types/issues";
import type {
  Issue,
  IssueEvidence,
  IssueSource,
  RepairAction,
  RepairPlan,
  Repairability,
  RootCauseType,
  VerificationStatus,
} from "@/lib/types/issues";
import type { IssueSignals } from "@/lib/server/load-dashboard-data";

describe("issue domain types", () => {
  it("exports canonical repairability and verification states needed by the first-phase repair loop", () => {
    const repairability: Repairability = "auto";
    const verification: VerificationStatus = "resolved";

    expect(repairability).toBe("auto");
    expect(verification).toBe("resolved");
    expect(REPAIRABILITIES).toEqual(["auto", "confirm", "manual"]);
    expect(VERIFICATION_STATUSES).toEqual(["resolved", "partially_resolved", "unresolved"]);
  });

  it("exports the full first-phase root cause enum list", () => {
    const rootCauseTypes: RootCauseType[] = [
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
    ];

    expect(ROOT_CAUSE_TYPES).toEqual([
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
    ]);
    expect(rootCauseTypes).toEqual(ROOT_CAUSE_TYPES);
  });

  it("supports canonical issue and root-cause records", () => {
    const source: IssueSource = "Channel";
    const evidence: IssueEvidence = {
      summary: "Discord channel is enabled but plugin is disabled.",
      detail: "channel.discord.enabled=true, plugins.discord.enabled=false",
      impactScope: "discord",
    };
    const action: RepairAction = {
      kind: "enable_plugin",
      label: "Enable Discord plugin",
      description: "Set plugins.discord.enabled to true",
    };
    const repairPlan: RepairPlan = {
      repairability: "confirm",
      summary: "Enable the Discord plugin and validate channel/plugin consistency.",
      steps: [
        "Enable plugins.discord in configuration.",
        "Reload or restart services if required.",
      ],
      actions: [action],
      fallbackManualSteps: ["Run openclaw config set plugins.discord.enabled true"],
    };
    const issue: Issue = {
      id: "issue-1",
      source,
      title: "Discord channel unavailable",
      summary: "Channel and plugin state mismatch",
      severity: "high",
      rootCause: {
        type: "channel_plugin_mismatch",
        evidence,
      },
      repairPlan,
      verificationStatus: "unresolved",
    };

    expect(issue.rootCause).toEqual({
      type: "channel_plugin_mismatch",
      evidence: {
        summary: "Discord channel is enabled but plugin is disabled.",
        detail: "channel.discord.enabled=true, plugins.discord.enabled=false",
        impactScope: "discord",
      },
    });
  });

  it("builds stable issue records from merged root-cause inputs", () => {
    const issues = buildIssues({
      signals: {
        channels: [
          {
            channelId: "discord",
            pluginId: "discord",
            channelEnabled: true,
            pluginEnabled: false,
            pluginInstalled: true
          }
        ],
        models: {
          primaryModelKey: "openai/gpt-5.4",
          candidateModelKeys: ["openai/gpt-5.3-codex"]
        },
        gateway: {
          reachable: "unreachable",
          error: "connect ECONNREFUSED"
        },
        logs: {
          excerpts: [
            "error agent=writer session=s-1 dispatch failed timeout waiting gateway"
          ],
          tokens: ["agent", "dispatch", "error", "gateway", "session", "timeout", "writer"],
          references: [
            {
              lineIndex: 0,
              agentId: "writer",
              sessionKey: "writer-main",
              sessionId: "s-1"
            }
          ],
          relatedSessionKeys: ["writer-main"],
          relatedAgentIds: ["writer"]
        }
      } satisfies IssueSignals
    });

    expect(issues.map((issue) => issue.id)).toEqual([
      "channel:channel_plugin_mismatch:discord",
      "config:primary_model_missing:openai/gpt-5.4",
      "config:gateway_unreachable:gateway",
      "agent:session_log_error_detected:writer-main",
      "agent:agent_dispatch_failure:writer-main"
    ]);
    expect(issues[0]).toMatchObject({
      source: "Channel",
      verificationStatus: "unresolved"
    });
  });
});
