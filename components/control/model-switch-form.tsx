"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { pushActionHistory } from "@/components/control/action-history";

export function ModelSwitchForm({
  currentModel,
  models
}: {
  currentModel: string;
  models: string[];
}) {
  const router = useRouter();
  const [selected, setSelected] = useState(currentModel);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();

  return (
    <div className="control-form">
      <label className="control-label">
        默认模型
        <select value={selected} onChange={(event) => setSelected(event.target.value)}>
          {models.map((model) => (
            <option key={model} value={model}>
              {model}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        className="action-button"
        disabled={pending}
        onClick={() => {
          if (
            !window.confirm(
              `确认将默认模型切换为“${selected}”吗？\n\n保存配置后将尝试执行 openclaw gateway restart 使 Gateway 加载新模型。`
            )
          ) {
            return;
          }

          startTransition(async () => {
            setMessage("");
            const response = await fetch("/api/control/switch-model", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ model: selected })
            });
            const result = (await response.json()) as {
              ok: boolean;
              stderr?: string;
              restartSkipped?: boolean;
              restartOk?: boolean;
              restartStderr?: string;
            };
            if (response.ok && result.ok) {
              let detail = `已切换为 ${selected}`;
              if (result.restartSkipped) {
                setMessage("模型已切换（未重启 Gateway，可能由环境变量跳过）");
              } else if (result.restartOk) {
                setMessage("模型已切换，Gateway 已重启");
              } else {
                const rs = result.restartStderr?.trim() || "未知错误";
                setMessage(`模型已切换，但 Gateway 重启失败：${rs}`);
                detail = `${detail}；重启失败：${rs}`;
                pushActionHistory({
                  label: "切换默认模型",
                  status: "error",
                  detail
                });
                router.refresh();
                return;
              }
              pushActionHistory({
                label: "切换默认模型",
                status: "success",
                detail
              });
              router.refresh();
              return;
            }
            const detail = result.stderr || "切换失败";
            setMessage(detail);
            pushActionHistory({
              label: "切换默认模型",
              status: "error",
              detail
            });
          });
        }}
      >
        {pending ? "切换中..." : "切换模型"}
      </button>
      {message ? <span className="action-feedback">{message}</span> : null}
    </div>
  );
}
