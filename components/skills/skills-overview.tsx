"use client";

import { useDeferredValue, useEffect, useMemo, useState } from "react";

import type { SkillDetails, SkillListEntry, SkillsDashboardData } from "@/lib/server/skills";

type SkillFilter = "all" | "eligible" | "missing";

function summarizeMissing(missing: SkillListEntry["missing"]) {
  return [
    ...missing.config.map((item) => `配置 ${item}`),
    ...missing.env.map((item) => `环境变量 ${item}`),
    ...missing.bins.map((item) => `命令 ${item}`),
    ...missing.anyBins.map((item) => `任选命令 ${item}`),
    ...missing.os.map((item) => `系统 ${item}`)
  ];
}

function skillStateLabel(skill: SkillListEntry) {
  if (skill.disabled) {
    return "已禁用";
  }

  if (skill.blockedByAllowlist) {
    return "被 allowlist 阻止";
  }

  return skill.eligible ? "可用" : "缺依赖";
}

function statusClassName(skill: SkillListEntry) {
  if (skill.eligible) {
    return "status-badge status-healthy";
  }

  return skill.disabled || skill.blockedByAllowlist
    ? "status-badge status-critical"
    : "status-badge status-warning";
}

export function SkillsOverview({ initialData }: { initialData?: SkillsDashboardData }) {
  const [data, setData] = useState<SkillsDashboardData | null>(initialData ?? null);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<SkillFilter>("all");
  const [expandedSkill, setExpandedSkill] = useState<string | null>(null);
  const [detailsBySkill, setDetailsBySkill] = useState<Record<string, SkillDetails | undefined>>({});
  const [loadingSkill, setLoadingSkill] = useState<string | null>(null);
  const [detailError, setDetailError] = useState<Record<string, string | undefined>>({});
  const [loadError, setLoadError] = useState("");
  const [status, setStatus] = useState<"loading" | "ready" | "error">(initialData ? "ready" : "loading");
  const deferredQuery = useDeferredValue(query);

  useEffect(() => {
    if (data) {
      return;
    }

    let cancelled = false;

    async function loadData() {
      setStatus("loading");
      setLoadError("");

      try {
        const response = await fetch("/api/skills", {
          cache: "no-store"
        });
        const payload = (await response.json()) as SkillsDashboardData | { error?: string };

        if (!response.ok) {
          throw new Error("error" in payload ? payload.error || "技能清单加载失败" : "技能清单加载失败");
        }

        if (!cancelled) {
          setData(payload as SkillsDashboardData);
          setStatus("ready");
        }
      } catch (error) {
        if (!cancelled) {
          setLoadError(error instanceof Error ? error.message : "技能清单加载失败");
          setStatus("error");
        }
      }
    }

    void loadData();

    return () => {
      cancelled = true;
    };
  }, [data]);

  const filteredSkills = useMemo(() => {
    if (!data) {
      return [];
    }

    const normalizedQuery = deferredQuery.trim().toLowerCase();

    return data.skills.filter((skill) => {
      if (filter === "eligible" && !skill.eligible) {
        return false;
      }

      if (filter === "missing" && skill.eligible) {
        return false;
      }

      if (!normalizedQuery) {
        return true;
      }

      const haystack = [skill.name, skill.description, skill.source, ...summarizeMissing(skill.missing)]
        .join(" ")
        .toLowerCase();

      return haystack.includes(normalizedQuery);
    });
  }, [data, deferredQuery, filter]);

  if (status === "loading" || !data) {
    return (
      <section className="control-zone control-zone-secondary skills-loading-shell">
        <header className="control-zone-header">
          <div>
            <p className="eyebrow">Inventory</p>
            <h2>Skills</h2>
            <p>页面先加载框架，再异步读取 skills 清单，避免首屏被 CLI 冷启动阻塞。</p>
          </div>
        </header>
        <div className="empty-state">
          <strong>技能清单加载中</strong>
          <p>正在调用本机 OpenClaw CLI 汇总可用 skills 与缺失依赖。</p>
        </div>
      </section>
    );
  }

  if (status === "error") {
    return (
      <section className="control-zone control-zone-secondary skills-loading-shell">
        <header className="control-zone-header">
          <div>
            <p className="eyebrow">Inventory</p>
            <h2>Skills</h2>
            <p>技能索引读取失败。</p>
          </div>
        </header>
        <div className="empty-state">
          <strong>技能清单加载失败</strong>
          <p>{loadError}</p>
        </div>
      </section>
    );
  }

  async function openSkillDetails(skillName: string) {
    if (expandedSkill === skillName) {
      setExpandedSkill(null);
      return;
    }

    setExpandedSkill(skillName);
    setDetailError((current) => ({ ...current, [skillName]: undefined }));

    if (detailsBySkill[skillName]) {
      return;
    }

    setLoadingSkill(skillName);

    try {
      const response = await fetch(`/api/skills/${encodeURIComponent(skillName)}`, {
        cache: "no-store"
      });
      const payload = (await response.json()) as SkillDetails | { error?: string };

      if (!response.ok) {
        throw new Error("error" in payload ? payload.error || "技能详情加载失败" : "技能详情加载失败");
      }

      setDetailsBySkill((current) => ({
        ...current,
        [skillName]: payload as SkillDetails
      }));
    } catch (error) {
      setDetailError((current) => ({
        ...current,
        [skillName]: error instanceof Error ? error.message : "技能详情加载失败"
      }));
    } finally {
      setLoadingSkill((current) => (current === skillName ? null : current));
    }
  }

  return (
    <div className="control-grid skills-page">
      <div className="models-primary-metrics">
        <article className="metric-card">
          <span className="metric-label">总数</span>
          <strong className="metric-value">{data.summary.total}</strong>
          <p>当前可见 skills。</p>
        </article>
        <article className="metric-card">
          <span className="metric-label">可用</span>
          <strong className="metric-value">{data.summary.eligible}</strong>
          <p>当前可直接使用。</p>
        </article>
        <article className="metric-card metric-card-quiet">
          <span className="metric-label">缺依赖</span>
          <strong className="metric-value">{data.summary.missingRequirements}</strong>
          <p>需要补命令或配置。</p>
        </article>
      </div>

      <section className="control-zone control-zone-secondary">
        <header className="control-zone-header">
          <div>
            <p className="eyebrow">Inventory</p>
            <h2>Skills</h2>
            <p>查看可用性、缺失项与技能详情。</p>
          </div>
        </header>
        <div className="models-toolbar">
          <label className="control-label models-primary-select">
            搜索 skills
            <input
              type="search"
              value={query}
              placeholder="按名称、描述、来源或缺失项筛选"
              onChange={(event) => setQuery(event.target.value)}
            />
          </label>
          <label className="control-label">
            状态
            <select value={filter} onChange={(event) => setFilter(event.target.value as SkillFilter)}>
              <option value="all">全部</option>
              <option value="eligible">只看可用</option>
              <option value="missing">只看缺依赖</option>
            </select>
          </label>
        </div>
        <div className="workbench-list skills-list">
          {filteredSkills.map((skill) => {
            const detail = detailsBySkill[skill.name];
            const missingItems = summarizeMissing(skill.missing);
            const isExpanded = expandedSkill === skill.name;
            const isLoading = loadingSkill === skill.name;
            const error = detailError[skill.name];
            const endpoint = `/api/skills/${encodeURIComponent(skill.name)}`;

            return (
              <article
                key={skill.name}
                className={`priority-card skills-item${skill.eligible ? "" : " priority-medium"}`}
              >
                <div className="skills-item-main">
                  <div className="priority-meta skills-item-meta">
                    <span>{skill.source}</span>
                    <span>{skill.bundled ? "bundled" : "managed"}</span>
                  </div>
                  <div className="priority-card-head skills-item-head">
                    <div className="skills-item-title">
                      <h3>{skill.emoji ? `${skill.emoji} ${skill.name}` : skill.name}</h3>
                      <p>{skill.description}</p>
                    </div>
                    <div className="skills-item-side">
                      <span className={`${statusClassName(skill)} skills-state-pill`}>
                        {skillStateLabel(skill)}
                      </span>
                      <button
                        type="button"
                        className="action-button action-secondary skills-detail-button"
                        data-endpoint={endpoint}
                        onClick={() => void openSkillDetails(skill.name)}
                      >
                        {isExpanded ? "收起详情" : isLoading ? "加载中..." : "查看详情"}
                      </button>
                    </div>
                  </div>
                </div>
                {missingItems.length > 0 ? (
                  <div className="priority-card-body skills-item-missing">
                    <strong>缺失项</strong>
                    <p>{missingItems.slice(0, 4).join(" · ")}</p>
                  </div>
                ) : null}
                <footer>
                  {isExpanded ? (
                    error ? (
                      <span className="action-feedback">{error}</span>
                    ) : detail ? (
                      <div className="workbench-list skills-detail-grid">
                        <article className="priority-card skills-detail-card">
                          <div className="priority-meta">
                            <span>Skill Key</span>
                            <span>{detail.skillKey}</span>
                          </div>
                          <p className="skills-detail-path">{detail.filePath}</p>
                          <footer className="skills-detail-path">{detail.baseDir}</footer>
                        </article>
                        <article className="priority-card skills-detail-card">
                          <div className="priority-meta">
                            <span>要求</span>
                            <span>{detail.always ? "always" : "optional"}</span>
                          </div>
                          <p>
                            {summarizeMissing(detail.requirements).length > 0
                              ? summarizeMissing(detail.requirements).join(" · ")
                              : "无额外要求"}
                          </p>
                          <footer>
                            {detail.install.length > 0
                              ? detail.install.map((item) => item.label).join(" · ")
                              : "暂无自动安装建议"}
                          </footer>
                        </article>
                      </div>
                    ) : (
                      <span className="action-feedback">准备加载详情...</span>
                    )
                  ) : null}
                </footer>
              </article>
            );
          })}
          {filteredSkills.length === 0 ? (
            <div className="empty-state">
              <strong>没有匹配的 skill</strong>
              <p>调整搜索词或筛选条件后再试。</p>
            </div>
          ) : null}
        </div>
      </section>
    </div>
  );
}
