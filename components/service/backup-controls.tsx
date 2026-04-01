"use client";

import { useEffect, useState, useTransition } from "react";

type BackupItem = {
  id: string;
  createdAt: string;
  fileCount: number;
};

export function BackupControls({
  backups,
  onChanged
}: {
  backups: BackupItem[];
  onChanged?: () => Promise<void> | void;
}) {
  const [selectedBackupId, setSelectedBackupId] = useState(backups[0]?.id ?? "");
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();

  useEffect(() => {
    if (!selectedBackupId && backups[0]?.id) {
      setSelectedBackupId(backups[0].id);
      return;
    }
    if (selectedBackupId && !backups.some((item) => item.id === selectedBackupId)) {
      setSelectedBackupId(backups[0]?.id ?? "");
    }
  }, [backups, selectedBackupId]);

  return (
    <div className="control-form">
      <div className="inline-actions">
        <button
          type="button"
          className="action-button"
          disabled={pending}
          onClick={() =>
            startTransition(async () => {
              setMessage("");
              const response = await fetch("/api/service/backups", {
                method: "POST"
              });
              const payload = (await response.json()) as {
                ok?: boolean;
                backup?: { id: string };
                error?: string;
              };
              if (!response.ok || payload.ok === false) {
                setMessage(payload.error ?? "创建备份失败");
                return;
              }
              setMessage(`已创建备份：${payload.backup?.id ?? "unknown"}`);
              await onChanged?.();
            })
          }
        >
          {pending ? "处理中..." : "创建备份"}
        </button>
      </div>

      <label className="control-label">
        选择恢复点
        <select
          value={selectedBackupId}
          onChange={(event) => setSelectedBackupId(event.target.value)}
          disabled={pending || backups.length === 0}
        >
          {backups.length === 0 ? (
            <option value="">暂无可用备份</option>
          ) : (
            backups.map((item) => (
              <option key={item.id} value={item.id}>
                {item.id} · {new Date(item.createdAt).toLocaleString("zh-CN")} · {item.fileCount} 文件
              </option>
            ))
          )}
        </select>
      </label>

      <div className="inline-actions">
        <button
          type="button"
          className="action-button action-secondary"
          disabled={pending || backups.length === 0 || !selectedBackupId}
          onClick={() => {
            if (!window.confirm("确认恢复该备份吗？将覆盖当前配置并重启 Gateway。")) {
              return;
            }

            startTransition(async () => {
              setMessage("");
              const response = await fetch("/api/service/backups/restore", {
                method: "POST",
                headers: {
                  "Content-Type": "application/json"
                },
                body: JSON.stringify({ backupId: selectedBackupId })
              });
              const payload = (await response.json()) as {
                ok?: boolean;
                error?: string;
              };
              if (!response.ok || payload.ok === false) {
                setMessage(payload.error ?? "恢复备份失败");
                return;
              }
              setMessage("备份已恢复并触发 Gateway 重启。");
              await onChanged?.();
            });
          }}
        >
          恢复备份
        </button>
      </div>

      {message ? <p className="action-log">{message}</p> : null}
    </div>
  );
}
