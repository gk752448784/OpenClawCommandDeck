"use client";

import { useEffect, useState } from "react";

type ServiceRuntimePayload = {
  version: string;
  gateway: {
    reachable: "reachable" | "unreachable" | "unknown";
    error: string | null;
  };
  checkedAt: string;
};

function gatewayStatusText(value: "reachable" | "unreachable" | "unknown") {
  if (value === "reachable") {
    return "可达";
  }
  if (value === "unreachable") {
    return "不可达";
  }
  return "未知";
}

export function RuntimePanel() {
  const [runtime, setRuntime] = useState<ServiceRuntimePayload | null>(null);
  const [error, setError] = useState<string>("");

  useEffect(() => {
    let mounted = true;
    void fetch("/api/service", { cache: "no-store" })
      .then(async (response) => {
        const payload = (await response.json()) as ServiceRuntimePayload & { error?: string };
        if (!mounted) {
          return;
        }
        if (!response.ok) {
          setError(payload.error ?? "加载服务状态失败");
          return;
        }
        setRuntime(payload);
      })
      .catch((reason) => {
        if (!mounted) {
          return;
        }
        setError(reason instanceof Error ? reason.message : "加载服务状态失败");
      });

    return () => {
      mounted = false;
    };
  }, []);

  if (!runtime && !error) {
    return <p className="action-log">加载服务状态中...</p>;
  }

  if (error) {
    return <p className="action-log">{error}</p>;
  }

  return (
    <>
      <div className="management-metrics management-metrics-compact management-metrics-compact-3">
        <div className="metric-card">
          <span className="metric-label">运行版本</span>
          <strong className="metric-value">{runtime?.version ?? "unknown"}</strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">可达性</span>
          <strong className="metric-value">
            {gatewayStatusText(runtime?.gateway.reachable ?? "unknown")}
          </strong>
        </div>
        <div className="metric-card">
          <span className="metric-label">检查时间</span>
          <strong className="metric-value">
            {runtime?.checkedAt
              ? new Date(runtime.checkedAt).toLocaleTimeString("zh-CN")
              : "未知"}
          </strong>
        </div>
      </div>
      {runtime?.gateway.error ? <p className="action-log">{runtime.gateway.error}</p> : null}
    </>
  );
}
