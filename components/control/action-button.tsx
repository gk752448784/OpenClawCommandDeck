"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { pushActionHistory } from "@/components/control/action-history";

export function ActionButton({
  action,
  payload,
  label,
  variant = "default",
  onSuccess,
  confirmMessage
}: {
  action: string;
  payload: Record<string, unknown>;
  label: string;
  variant?: "default" | "danger" | "secondary";
  onSuccess?: () => void;
  confirmMessage?: string;
}) {
  const router = useRouter();
  const [message, setMessage] = useState<string>("");
  const [pending, startTransition] = useTransition();

  return (
    <div className="action-button-wrap">
      <button
        type="button"
        className={`action-button action-${variant}`}
        disabled={pending}
        onClick={() => {
          if (confirmMessage && !window.confirm(confirmMessage)) {
            return;
          }

          startTransition(async () => {
            setMessage("");
            const response = await fetch(`/api/control/${action}`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json"
              },
              body: JSON.stringify(payload)
            });
            const result = (await response.json()) as {
              ok: boolean;
              stdout?: string;
              stderr?: string;
              error?: string;
            };
            if (response.ok && result.ok) {
              setMessage("已执行");
              pushActionHistory({
                label,
                status: "success",
                detail: result.stdout || "操作已经成功执行。"
              });
              router.refresh();
              onSuccess?.();
              return;
            }

            const errorMessage = result.stderr || result.error || "执行失败";
            setMessage(errorMessage);
            pushActionHistory({
              label,
              status: "error",
              detail: errorMessage
            });
          });
        }}
      >
        {pending ? "执行中..." : label}
      </button>
      {message ? <span className="action-feedback">{message}</span> : null}
    </div>
  );
}
