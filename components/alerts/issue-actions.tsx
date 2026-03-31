"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import type { Issue } from "@/lib/types/issues";

function confirmationMessage(issue: Issue) {
  if (issue.repairPlan.repairability !== "confirm") {
    return null;
  }

  return `将执行“${issue.repairPlan.summary}”。这类修复可能影响当前运行状态，是否继续？`;
}

export function IssueActions({ issue }: { issue: Issue }) {
  const router = useRouter();
  const [repairMessage, setRepairMessage] = useState("");
  const [verifyMessage, setVerifyMessage] = useState("");
  const [pendingRepair, startRepairTransition] = useTransition();
  const [pendingVerify, startVerifyTransition] = useTransition();

  return (
    <div className="issue-actions">
      {issue.repairPlan.actions.length > 0 ? (
        <button
          type="button"
          className={`action-button ${
            issue.repairPlan.repairability === "manual" ? "action-secondary" : "action-default"
          }`}
          disabled={pendingRepair || issue.repairPlan.repairability === "manual"}
          onClick={() => {
            const confirmMessage = confirmationMessage(issue);
            if (confirmMessage && !window.confirm(confirmMessage)) {
              return;
            }

            startRepairTransition(async () => {
              setRepairMessage("");
              const response = await fetch(`/api/issues/${issue.id}/repair`, {
                method: "POST",
                headers: {
                  "Content-Type": "application/json"
                },
                body: JSON.stringify({ confirm: true })
              });
              const payload = (await response.json()) as {
                ok: boolean;
                stdout?: string;
                stderr?: string;
                error?: string;
              };

              if (response.ok && payload.ok) {
                setRepairMessage(payload.stdout || "修复动作已执行。");
                router.refresh();
                return;
              }

              setRepairMessage(payload.stderr || payload.error || "修复执行失败");
            });
          }}
        >
          {pendingRepair ? "修复中..." : issue.repairPlan.actions[0]?.label ?? "执行修复"}
        </button>
      ) : null}

      <button
        type="button"
        className="action-button action-secondary"
        disabled={pendingVerify}
        onClick={() => {
          startVerifyTransition(async () => {
            setVerifyMessage("");
            const response = await fetch(`/api/issues/${issue.id}/verify`, {
              method: "POST"
            });
            const payload = (await response.json()) as {
              status: string;
              summary?: string;
              error?: string;
            };

            if (response.ok) {
              setVerifyMessage(payload.summary || payload.status);
              router.refresh();
              return;
            }

            setVerifyMessage(payload.error || "验证失败");
          });
        }}
      >
        {pendingVerify ? "验证中..." : "重新验证"}
      </button>

      {repairMessage ? <span className="action-feedback">{repairMessage}</span> : null}
      {verifyMessage ? <span className="action-feedback">{verifyMessage}</span> : null}
    </div>
  );
}
