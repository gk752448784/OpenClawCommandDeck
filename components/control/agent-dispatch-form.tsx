"use client";

import { useState, useTransition } from "react";
import { pushActionHistory } from "@/components/control/action-history";

export function AgentDispatchForm({
  agents,
  initialAgentId,
  title = "发送给代理",
  placeholder = "例如：整理今天的待办并给出下一步建议",
  showAgentSelect = true,
  submitLabel = "发送任务",
  compact = false
}: {
  agents: Array<{ id: string; label: string }>;
  initialAgentId?: string;
  title?: string;
  placeholder?: string;
  showAgentSelect?: boolean;
  submitLabel?: string;
  compact?: boolean;
}) {
  const [agentId, setAgentId] = useState(initialAgentId ?? agents[0]?.id ?? "main");
  const [message, setMessage] = useState("");
  const [result, setResult] = useState("");
  const [pending, startTransition] = useTransition();

  return (
    <div className={`control-form${compact ? " compact-control-form" : ""}`}>
      {showAgentSelect ? (
        <label className="control-label">
          {title}
          <select value={agentId} onChange={(event) => setAgentId(event.target.value)}>
            {agents.map((agent) => (
              <option key={agent.id} value={agent.id}>
                {agent.label}
              </option>
            ))}
          </select>
        </label>
      ) : (
        <div className="control-label">
          {title}
          <strong>{agents.find((agent) => agent.id === agentId)?.label ?? agentId}</strong>
        </div>
      )}
      <label className="control-label">
        指令
        <textarea
          value={message}
          onChange={(event) => setMessage(event.target.value)}
          placeholder={placeholder}
        />
      </label>
      <button
        type="button"
        className="action-button"
        disabled={pending || message.trim().length === 0}
        onClick={() => {
          startTransition(async () => {
            setResult("");
            const response = await fetch("/api/control/dispatch-agent", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ agentId, message })
            });
            const payload = (await response.json()) as {
              ok: boolean;
              stdout?: string;
              stderr?: string;
            };
            const nextResult = payload.ok ? payload.stdout || "已发送" : payload.stderr || "发送失败";
            setResult(nextResult);
            pushActionHistory({
              label: `发送任务给 ${agentId}`,
              status: payload.ok ? "success" : "error",
              detail: nextResult
            });
          });
        }}
      >
        {pending ? "发送中..." : submitLabel}
      </button>
      {result ? <pre className="action-log">{result}</pre> : null}
    </div>
  );
}
