import { describe, expect, it } from "vitest";

import { buildSessionRepairSignalsModel } from "@/lib/selectors/session-repair-signals";
import type { SessionsSnapshot } from "@/lib/adapters/sessions";
import type { LogSignals } from "@/lib/signals/logs";
import type { Issue } from "@/lib/types/issues";

const sessions: SessionsSnapshot = {
  count: 1,
  sessions: [
    {
      sessionId: "sess-1",
      key: "session:writer:discord:writer-main",
      updatedAt: Date.now(),
      ageMs: 90_000,
      model: "openai/gpt-5.4",
      kind: "chat",
      percentUsed: 42,
      agentId: "writer"
    }
  ]
};

const issues: Issue[] = [
  {
    id: "agent:session_log_error_detected:session:writer:discord:writer-main",
    source: "Agent",
    title: "Writer 会话日志出现错误",
    summary: "最近一条日志包含 dispatch failure。",
    severity: "high",
    rootCause: {
      type: "session_log_error_detected",
      evidence: {
        summary: "dispatch failed session=writer-main",
        detail: "retry exhausted",
        impactScope: "session:writer:discord:writer-main"
      }
    },
    repairPlan: {
      repairability: "manual",
      summary: "先排查调度失败原因，再决定是否重试。",
      steps: ["查看最近调度日志", "确认目标会话仍可用"],
      actions: [],
      fallbackManualSteps: ["手动检查代理和会话状态"]
    },
    verificationStatus: "unresolved"
  }
];

const logs: LogSignals = {
  excerpts: ["dispatch failed session=writer-main agent=writer timeout"],
  tokens: ["dispatch", "failed", "writer"],
  references: [
    {
      lineIndex: 0,
      agentId: "writer",
      sessionKey: "session:writer:discord:writer-main",
      sessionId: null
    }
  ],
  relatedSessionKeys: ["session:writer:discord:writer-main"],
  relatedAgentIds: ["writer"]
};

describe("session repair signals selector", () => {
  it("maps log-related issues back to sessions and aggregates counts", () => {
    const model = buildSessionRepairSignalsModel({
      sessions,
      issues,
      logs
    });

    expect(model.sessionIssueCounts["session:writer:discord:writer-main"]).toBe(1);
    expect(model.agentIssueCounts.writer).toBe(1);
    expect(model.items[0]).toMatchObject({
      agentId: "writer",
      sessionKey: "session:writer:discord:writer-main",
      excerpt: "dispatch failed session=writer-main agent=writer timeout"
    });
  });
});
