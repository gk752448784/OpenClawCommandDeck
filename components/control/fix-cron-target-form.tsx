"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { pushActionHistory } from "@/components/control/action-history";

export function FixCronTargetForm({
  cronId,
  defaultChannel = "feishu",
  defaultTarget = ""
}: {
  cronId: string;
  defaultChannel?: string;
  defaultTarget?: string;
}) {
  const router = useRouter();
  const [channel, setChannel] = useState(defaultChannel);
  const [target, setTarget] = useState(defaultTarget);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();

  return (
    <div className="control-form compact-control-form">
      <label className="control-label">
        渠道
        <input value={channel} onChange={(event) => setChannel(event.target.value)} />
      </label>
      <label className="control-label">
        目标
        <input
          value={target}
          onChange={(event) => setTarget(event.target.value)}
          placeholder="chatId / user:openId / chat:chatId"
        />
      </label>
      <button
        type="button"
        className="action-button"
        disabled={pending || target.trim().length === 0}
        onClick={() => {
          startTransition(async () => {
            setMessage("");
            const response = await fetch("/api/control/fix-cron-target", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ id: cronId, channel, target })
            });
            const result = (await response.json()) as { ok: boolean; stderr?: string };
            if (response.ok && result.ok) {
              setMessage("投递目标已更新");
              pushActionHistory({
                label: "修复计划任务目标",
                status: "success",
                detail: `${channel} → ${target}`
              });
              router.refresh();
              return;
            }
            const detail = result.stderr || "更新失败";
            setMessage(detail);
            pushActionHistory({
              label: "修复计划任务目标",
              status: "error",
              detail
            });
          });
        }}
      >
        {pending ? "保存中..." : "保存投递目标"}
      </button>
      {message ? <span className="action-feedback">{message}</span> : null}
    </div>
  );
}
