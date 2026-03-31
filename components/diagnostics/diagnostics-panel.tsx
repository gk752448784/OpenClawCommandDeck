"use client";

import { useEffect, useState } from "react";

import { VerificationBadge } from "@/components/issues/verification-badge";
import { SectionCard } from "@/components/shared/section-card";
import type { DiagnosticsModel } from "@/lib/types/view-models";

export function DiagnosticsPanel() {
  const [data, setData] = useState<DiagnosticsModel | null>(null);
  const [error, setError] = useState<string>("");
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    if (status !== "loading") {
      return;
    }

    const timer = window.setInterval(() => {
      setProgress((current) => Math.min(current + (current < 56 ? 12 : current < 82 ? 6 : 2), 92));
    }, 220);

    return () => {
      window.clearInterval(timer);
    };
  }, [status]);

  async function runDiagnostics() {
    setStatus("loading");
    setProgress(8);
    setError("");

    try {
      const response = await fetch("/api/diagnostics", {
        cache: "no-store"
      });
      const payload = (await response.json()) as DiagnosticsModel | { error?: string };

      if (!response.ok) {
        throw new Error("error" in payload ? payload.error || "诊断加载失败" : "诊断加载失败");
      }

      setData(payload as DiagnosticsModel);
      setProgress(100);
      setStatus("success");
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "诊断加载失败");
      setStatus("error");
    }
  }

  if (status === "idle") {
    return (
      <SectionCard title="系统诊断" subtitle="需要时再执行检查">
        <div className="diagnostics-trigger-card">
          <div>
            <strong>诊断不会自动打满页面</strong>
            <p>点击后再采集运行时状态、最近日志和安全审计，避免每次进入页面都触发重型检查。</p>
          </div>
          <button className="action-button" type="button" onClick={() => void runDiagnostics()}>
            开始诊断
          </button>
        </div>
      </SectionCard>
    );
  }

  if (status === "loading") {
    return (
      <SectionCard title="系统诊断" subtitle="正在采集运行时状态">
        <div className="diagnostics-loading-card">
          <div className="diagnostics-loading-header">
            <strong>正在执行诊断</strong>
            <span>{progress}%</span>
          </div>
          <div className="diagnostics-progress-track">
            <div className="diagnostics-progress-bar" style={{ width: `${progress}%` }} />
          </div>
          <div className="diagnostics-step-list">
            <span>读取 Gateway 状态</span>
            <span>汇总安全审计</span>
            <span>抓取最近日志</span>
          </div>
        </div>
      </SectionCard>
    );
  }

  if (status === "error") {
    return (
      <SectionCard title="系统诊断" subtitle="诊断执行失败">
        <div className="empty-state">
          <strong>诊断加载失败</strong>
          <p>{error}</p>
          <div className="inline-actions">
            <button className="action-button" type="button" onClick={() => void runDiagnostics()}>
              重新诊断
            </button>
          </div>
        </div>
      </SectionCard>
    );
  }

  if (!data) {
    return null;
  }

  return (
    <div className="control-grid">
      <SectionCard title="运行诊断" subtitle="状态快照">
        <div className="diagnostics-grid">
          <article className="priority-card">
            <div className="priority-meta">
              <span>运行时</span>
              <span>{data.runtimeVersion}</span>
            </div>
            <h3>{data.gateway.summary}</h3>
            <p>{data.gateway.detail}</p>
          </article>
          <article className="priority-card">
            <div className="priority-meta">
              <span>安全审计</span>
              <span>重点风险</span>
            </div>
            <h3>{data.security.critical} 个严重项</h3>
            <p>
              警告 {data.security.warn} 项，信息 {data.security.info} 项。
            </p>
          </article>
        </div>
        <div className="inline-actions">
          <button className="action-button action-secondary" type="button" onClick={() => void runDiagnostics()}>
            重新诊断
          </button>
        </div>
      </SectionCard>

      <SectionCard title="风险项" subtitle="优先处理">
        <div className="workbench-list">
          {data.findings.map((finding) => (
            <article key={finding.id} className="priority-card priority-high">
              <div className="priority-meta">
                <span>{finding.severity}</span>
                <span>{finding.id}</span>
              </div>
              <h3>{finding.title}</h3>
              <p>{finding.detail}</p>
              {finding.remediation ? <footer>{finding.remediation}</footer> : null}
            </article>
          ))}
        </div>
      </SectionCard>

      <SectionCard title="修复证据" subtitle="诊断与问题闭环共享的线索">
        <div className="workbench-list">
          {data.issueEvidence.map((issue) => (
            <article key={issue.id} className="priority-card priority-high">
              <div className="priority-meta">
                <span>{issue.source}</span>
                <span>{issue.repairability}</span>
              </div>
              <h3>{issue.title}</h3>
              <p>{issue.summary}</p>
              <footer>
                <VerificationBadge status={issue.verificationStatus} />
              </footer>
            </article>
          ))}
        </div>
      </SectionCard>

      <SectionCard title="最近日志" subtitle="近 12 条">
        <pre className="action-log">{data.logs.join("\n")}</pre>
      </SectionCard>
    </div>
  );
}
