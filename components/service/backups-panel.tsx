"use client";

import { useCallback, useEffect, useState } from "react";

import { BackupControls } from "@/components/service/backup-controls";

type BackupItem = {
  id: string;
  createdAt: string;
  fileCount: number;
};

export function BackupsPanel() {
  const [backups, setBackups] = useState<BackupItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const loadBackups = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/service/backups", {
        cache: "no-store"
      });
      const payload = (await response.json()) as { items?: BackupItem[]; error?: string };
      if (!response.ok) {
        setError(payload.error ?? "加载备份列表失败");
        return;
      }
      setBackups(Array.isArray(payload.items) ? payload.items : []);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "加载备份列表失败");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadBackups();
  }, [loadBackups]);

  if (loading) {
    return <p className="action-log">加载备份列表中...</p>;
  }

  if (error) {
    return <p className="action-log">{error}</p>;
  }

  return <BackupControls backups={backups} onChanged={loadBackups} />;
}
