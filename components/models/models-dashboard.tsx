"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { pushActionHistory } from "@/components/control/action-history";
import type { ModelsDashboardModel } from "@/lib/selectors/models-dashboard";

export function ModelsDashboard({ model }: { model: ModelsDashboardModel }) {
  const router = useRouter();
  const [primaryModel, setPrimaryModel] = useState(model.primaryModel.key);
  const [items, setItems] = useState(
    model.models.map((entry) => ({
      key: entry.key,
      alias: entry.alias,
      allowed: entry.allowed
    }))
  );
  const [providerDrafts, setProviderDrafts] = useState<
    Array<{
      key: string;
      baseUrl: string;
      api: string;
      apiKey: string;
    }>
  >([]);
  const [modelDrafts, setModelDrafts] = useState<
    Array<{
      provider: string;
      id: string;
      name: string;
      input: string[];
      contextWindow: number | null;
      maxTokens: number | null;
      reasoning: boolean;
    }>
  >([]);
  const [showProviderForm, setShowProviderForm] = useState(false);
  const [showModelForm, setShowModelForm] = useState(false);
  const [showModelAdvanced, setShowModelAdvanced] = useState(false);
  const [discoveringProvider, setDiscoveringProvider] = useState("");
  const [discoveredBatch, setDiscoveredBatch] = useState<{
    provider: string;
    items: Array<{
      key: string;
      provider: string;
      id: string;
      name: string;
      input: string[];
      contextWindow: number | null;
      maxTokens: number | null;
      thinking: boolean;
      selected: boolean;
      mode: "overwrite" | "add";
    }>;
  } | null>(null);
  const [importedDiscovered, setImportedDiscovered] = useState<
    Array<{
      key: string;
      provider: string;
      id: string;
      name: string;
      input: string[];
      contextWindow: number | null;
      maxTokens: number | null;
      thinking: boolean;
    }>
  >([]);
  const [providerRemovals, setProviderRemovals] = useState<string[]>([]);
  const [modelRemovals, setModelRemovals] = useState<string[]>([]);
  const [providerForm, setProviderForm] = useState({
    key: "",
    baseUrl: "",
    api: "openai-completions",
    apiKey: ""
  });
  const [modelForm, setModelForm] = useState({
    provider: model.providers[0]?.key ?? "",
    id: "",
    name: "",
    input: "text",
    contextWindow: "",
    maxTokens: "",
    reasoning: false
  });
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();

  const providerKeys = useMemo(
    () => [...new Set([...model.providers.map((entry) => entry.key), ...providerDrafts.map((entry) => entry.key)])],
    [model.providers, providerDrafts]
  );

  const providerCards = useMemo(
    () => [
      ...model.providers.map((provider) => ({
        ...provider,
        isDraft: false
      })),
      ...providerDrafts.map((provider) => ({
        key: provider.key,
        baseUrl: provider.baseUrl,
        api: provider.api,
        modelCount: modelDrafts.filter((entry) => entry.provider === provider.key).length,
        isPrimaryProvider: provider.key === primaryModel.split("/")[0],
        hasMultimodal: modelDrafts.some(
          (entry) => entry.provider === provider.key && entry.input.includes("image")
        ),
        isDraft: true
      }))
    ],
    [model.providers, modelDrafts, primaryModel, providerDrafts]
  );

  const apiTypes = useMemo(
    () =>
      [
        ...new Set([
          "openai-completions",
          ...model.providers
            .map((provider) => provider.api)
            .filter((value): value is string => Boolean(value)),
          ...providerDrafts
            .map((provider) => provider.api)
            .filter((value): value is string => Boolean(value))
        ])
      ],
    [model.providers, providerDrafts]
  );

  const modelRows = useMemo(() => {
    const rowMap = new Map<
      string,
      ModelsDashboardModel["models"][number] & { isDraft: boolean; isImported: boolean }
    >();

    for (const entry of model.models) {
      rowMap.set(entry.key, {
        ...entry,
        isDraft: false,
        isImported: false
      });
    }

    for (const entry of modelDrafts) {
      const key = `${entry.provider}/${entry.id}`;
      rowMap.set(key, {
        key,
        provider: entry.provider,
        id: entry.id,
        name: entry.name || entry.id,
        alias: items.find((item) => item.key === key)?.alias ?? "",
        allowed: items.find((item) => item.key === key)?.allowed ?? true,
        isPrimary: key === primaryModel,
        contextWindow: entry.contextWindow,
        maxTokens: entry.maxTokens,
        input: entry.input,
        reasoning: entry.reasoning,
        isDraft: true,
        isImported: false
      });
    }

    for (const entry of importedDiscovered) {
      rowMap.set(entry.key, {
        key: entry.key,
        provider: entry.provider,
        id: entry.id,
        name: entry.name || entry.id,
        alias: items.find((item) => item.key === entry.key)?.alias ?? "",
        allowed: items.find((item) => item.key === entry.key)?.allowed ?? false,
        isPrimary: entry.key === primaryModel,
        contextWindow: entry.contextWindow,
        maxTokens: entry.maxTokens,
        input: entry.input,
        reasoning: entry.thinking,
        isDraft: false,
        isImported: true
      });
    }

    return Array.from(rowMap.values());
  }, [importedDiscovered, items, model.models, modelDrafts, primaryModel]);

  const hasChanges = useMemo(
    () =>
      primaryModel !== model.primaryModel.key ||
      providerDrafts.length > 0 ||
      modelDrafts.length > 0 ||
      importedDiscovered.length > 0 ||
      providerRemovals.length > 0 ||
      modelRemovals.length > 0 ||
      items.some((item) => {
        const initial = model.models.find((entry) => entry.key === item.key);
        return initial ? initial.alias !== item.alias || initial.allowed !== item.allowed : true;
      }),
    [
      items,
      importedDiscovered.length,
      model.models,
      model.primaryModel.key,
      modelDrafts.length,
      modelRemovals.length,
      primaryModel,
      providerDrafts.length,
      providerRemovals.length
    ]
  );

  const primaryAllowed = items.some((item) => item.key === primaryModel && item.allowed);
  const inputPreview = modelForm.input
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

  function addProviderDraft() {
    const key = providerForm.key.trim();
    const baseUrl = providerForm.baseUrl.trim();

    if (!key || !baseUrl) {
      setMessage("新增服务商需要填写 key 和 baseUrl。");
      return;
    }

    if (!/^[a-zA-Z0-9_-]+$/.test(key)) {
      setMessage("服务商 key 只允许字母、数字、- 和 _。");
      return;
    }

    if (providerKeys.includes(key)) {
      setMessage(`服务商 ${key} 已存在。`);
      return;
    }

    setProviderDrafts((prev) => [
      ...prev,
      {
        key,
        baseUrl,
        api: providerForm.api.trim() || "openai-completions",
        apiKey: providerForm.apiKey.trim()
      }
    ]);
    setShowProviderForm(false);
    setProviderForm({
      key: "",
      baseUrl: "",
      api: "openai-completions",
      apiKey: ""
    });
    setModelForm((prev) => ({
      ...prev,
      provider: prev.provider || key
    }));
    setMessage(`已加入未保存服务商：${key}`);
  }

  function openModelForm(provider?: string) {
    setShowModelForm(true);
    setShowModelAdvanced(false);
    setModelForm((prev) => ({
      ...prev,
      provider: provider ?? prev.provider ?? providerKeys[0] ?? ""
    }));
  }

  function addModelDraft() {
    const provider = modelForm.provider.trim();
    const id = modelForm.id.trim();
    const key = `${provider}/${id}`;

    if (!provider || !id) {
      setMessage("新增模型需要先选择服务商并填写 model id。");
      return;
    }

    if (!providerKeys.includes(provider)) {
      setMessage(`服务商 ${provider} 不存在。`);
      return;
    }

    if (modelRows.some((entry) => entry.key === key)) {
      setMessage(`模型 ${key} 已存在。`);
      return;
    }

    const contextWindow = modelForm.contextWindow.trim()
      ? Number(modelForm.contextWindow.trim())
      : null;
    const maxTokens = modelForm.maxTokens.trim() ? Number(modelForm.maxTokens.trim()) : null;

    if ((contextWindow !== null && Number.isNaN(contextWindow)) || (maxTokens !== null && Number.isNaN(maxTokens))) {
      setMessage("上下文窗口和最大输出必须是数字。");
      return;
    }

    const input = modelForm.input
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);

    setModelDrafts((prev) => [
      ...prev,
      {
        provider,
        id,
        name: modelForm.name.trim(),
        input: input.length ? input : ["text"],
        contextWindow,
        maxTokens,
        reasoning: modelForm.reasoning
      }
    ]);
    setItems((prev) => [
      ...prev,
      {
        key,
        alias: "",
        allowed: true
      }
    ]);
    setShowModelForm(false);
    setShowModelAdvanced(false);
    setModelForm((prev) => ({
      ...prev,
      id: "",
      name: "",
      input: "text",
      contextWindow: "",
      maxTokens: "",
      reasoning: false
    }));
    setMessage(`已加入未保存模型：${key}`);
  }

  async function discoverProviderModels(providerKey: string) {
    const draftProvider = providerDrafts.find((entry) => entry.key === providerKey);

    setDiscoveringProvider(providerKey);
    setMessage("");

    try {
      const response = await fetch("/api/models/discover", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          providerKey,
          ...(draftProvider
            ? {
                baseUrl: draftProvider.baseUrl,
                apiType: draftProvider.api,
                apiKey: draftProvider.apiKey
              }
            : {})
        })
      });
      const result = (await response.json()) as {
        ok?: boolean;
        error?: string;
        models?: Array<{
          provider: string;
          id: string;
          name: string;
          input: string[];
          contextWindow: number | null;
          maxTokens: number | null;
          thinking: boolean;
        }>;
      };

      if (!response.ok || !result.ok || !Array.isArray(result.models)) {
        setMessage(result.error || "获取模型失败");
        return;
      }

      const existingKeys = new Set(modelRows.map((entry) => entry.key));

      setDiscoveredBatch({
        provider: providerKey,
        items: result.models.map((entry) => ({
          ...entry,
          key: `${entry.provider}/${entry.id}`,
          selected: true,
          mode: existingKeys.has(`${entry.provider}/${entry.id}`) ? "overwrite" : "add"
        }))
      });
      setMessage(`已获取 ${result.models.length} 个模型，请确认后导入。`);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "获取模型失败");
    } finally {
      setDiscoveringProvider("");
    }
  }

  function importDiscoveredSelection() {
    if (!discoveredBatch) {
      return;
    }

    const selected = discoveredBatch.items.filter((entry) => entry.selected);

    if (!selected.length) {
      setMessage("请先选择至少一个模型。");
      return;
    }

    setImportedDiscovered((prev) => {
      const next = new Map(prev.map((entry) => [entry.key, entry]));
      for (const entry of selected) {
        next.set(entry.key, {
          key: entry.key,
          provider: entry.provider,
          id: entry.id,
          name: entry.name,
          input: entry.input,
          contextWindow: entry.contextWindow,
          maxTokens: entry.maxTokens,
          thinking: entry.thinking
        });
      }
      return Array.from(next.values());
    });

    setItems((prev) => {
      const next = [...prev];
      for (const entry of selected) {
        if (!next.some((item) => item.key === entry.key)) {
          next.push({
            key: entry.key,
            alias: "",
            allowed: false
          });
        }
      }
      return next;
    });

    setDiscoveredBatch(null);
    setMessage(`已加入 ${selected.length} 个待导入模型。`);
  }

  function removeProvider(providerKey: string) {
    if (providerDrafts.some((entry) => entry.key === providerKey)) {
      setProviderDrafts((prev) => prev.filter((entry) => entry.key !== providerKey));
      setModelDrafts((prev) => prev.filter((entry) => entry.provider !== providerKey));
      setImportedDiscovered((prev) => prev.filter((entry) => entry.provider !== providerKey));
      setItems((prev) => prev.filter((entry) => !entry.key.startsWith(`${providerKey}/`)));
      setMessage(`已移除未保存服务商：${providerKey}`);
      return;
    }

    if (providerKey === primaryModel.split("/")[0]) {
      setMessage("当前默认主模型所在服务商不能删除。");
      return;
    }

    const providerModelKeys = modelRows
      .filter((entry) => entry.provider === providerKey)
      .map((entry) => entry.key);

    if (providerModelKeys.some((key) => key === primaryModel)) {
      setMessage("当前默认主模型所在服务商不能删除。");
      return;
    }

    setModelDrafts((prev) => prev.filter((entry) => entry.provider !== providerKey));
    setImportedDiscovered((prev) => prev.filter((entry) => entry.provider !== providerKey));
    setItems((prev) =>
      prev
        .filter((entry) => !providerModelKeys.includes(entry.key) || !entry.key.startsWith(`${providerKey}/`))
        .map((entry) =>
          providerModelKeys.includes(entry.key) ? { ...entry, allowed: false } : entry
        )
    );
    setModelRemovals((prev) => [...new Set([...prev, ...providerModelKeys])]);
    setProviderRemovals((prev) => [...new Set([...prev, providerKey])]);
    setMessage(`已加入删除队列：${providerKey}，并包含其下 ${providerModelKeys.length} 个模型。`);
  }

  function removeModel(modelKey: string) {
    if (modelKey === primaryModel) {
      setMessage("当前默认主模型不能删除。");
      return;
    }

    const [providerKey] = modelKey.split("/");
    const draftMatch = modelDrafts.find((entry) => `${entry.provider}/${entry.id}` === modelKey);

    if (draftMatch) {
      setModelDrafts((prev) => prev.filter((entry) => `${entry.provider}/${entry.id}` !== modelKey));
      setImportedDiscovered((prev) => prev.filter((entry) => entry.key !== modelKey));
      setItems((prev) => prev.filter((entry) => entry.key !== modelKey));
      setMessage(`已移除未保存模型：${modelKey}`);
      return;
    }

    setImportedDiscovered((prev) => prev.filter((entry) => entry.key !== modelKey));
    setModelRemovals((prev) => [...new Set([...prev, modelKey])]);
    setItems((prev) =>
      prev.map((entry) => (entry.key === modelKey ? { ...entry, allowed: false } : entry))
    );
    setMessage(`已加入删除队列：${modelKey}`);

    const remaining = modelRows.filter(
      (entry) => entry.provider === providerKey && entry.key !== modelKey && !modelRemovals.includes(entry.key)
    );

    if (!remaining.length) {
      setProviderRemovals((prev) => [...new Set([...prev, providerKey])]);
    }
  }

  return (
    <div className="models-layout">
      <section className="models-hero">
        <div className="models-primary-card">
          <p className="eyebrow">当前主模型</p>
          <h2>{model.primaryModel.name}</h2>
          <div className="management-tags">
            <span className="management-tag">{model.primaryModel.key}</span>
            <span className="management-tag">{model.primaryModel.provider}</span>
            {model.primaryModel.alias ? (
              <span className="management-tag">别名：{model.primaryModel.alias}</span>
            ) : null}
          </div>
        </div>
        <div className="models-primary-metrics">
          <article className="metric-card">
            <span className="metric-label">上下文窗口</span>
            <strong className="metric-value">
              {model.primaryModel.contextWindow?.toLocaleString() ?? "未知"}
            </strong>
          </article>
          <article className="metric-card">
            <span className="metric-label">最大输出</span>
            <strong className="metric-value">
              {model.primaryModel.maxTokens?.toLocaleString() ?? "未知"}
            </strong>
          </article>
          <article className="metric-card">
            <span className="metric-label">输入能力</span>
            <strong className="metric-value">
              {model.primaryModel.input.length ? model.primaryModel.input.join(" / ") : "text"}
            </strong>
          </article>
        </div>
      </section>

      <section className="deck-section">
        <header className="deck-section-header">
          <div>
            <h2>服务商</h2>
            <p>当前已加载的 provider 与模型目录。</p>
          </div>
          <button
            type="button"
            className="action-button action-secondary"
            onClick={() => setShowProviderForm((value) => !value)}
          >
            {showProviderForm ? "收起服务商表单" : "新增服务商"}
          </button>
        </header>
        {showProviderForm ? (
          <div className="control-form models-inline-form">
            <div className="models-form-grid">
              <label className="control-label">
                provider key
                <input
                  value={providerForm.key}
                  onChange={(event) =>
                    setProviderForm((prev) => ({ ...prev, key: event.target.value }))
                  }
                  placeholder="例如 bailian"
                />
              </label>
              <label className="control-label">
                API 类型
                <select
                  value={providerForm.api}
                  onChange={(event) =>
                    setProviderForm((prev) => ({ ...prev, api: event.target.value }))
                  }
                >
                  {apiTypes.map((apiType) => (
                    <option key={apiType} value={apiType}>
                      {apiType}
                    </option>
                  ))}
                </select>
              </label>
              <label className="control-label">
                baseUrl
                <input
                  value={providerForm.baseUrl}
                  onChange={(event) =>
                    setProviderForm((prev) => ({ ...prev, baseUrl: event.target.value }))
                  }
                  placeholder="https://..."
                />
              </label>
              <label className="control-label">
                API Key
                <input
                  value={providerForm.apiKey}
                  onChange={(event) =>
                    setProviderForm((prev) => ({ ...prev, apiKey: event.target.value }))
                  }
                  placeholder="可留空"
                />
              </label>
            </div>
            <div className="models-form-actions">
              <button
                type="button"
                className="action-button action-secondary"
                onClick={() => {
                  setShowProviderForm(false);
                  setProviderForm({
                    key: "",
                    baseUrl: "",
                    api: "openai-completions",
                    apiKey: ""
                  });
                }}
              >
                取消
              </button>
              <button type="button" className="action-button" onClick={addProviderDraft}>
                加入本次更改
              </button>
            </div>
          </div>
        ) : null}
        <div className="models-provider-grid">
          {providerCards.map((provider) => (
            <article key={provider.key} className="management-card">
              <div className="management-card-top">
                <div>
                  <div className="management-card-meta">
                    <span>{provider.key}</span>
                    {provider.isPrimaryProvider ? <span>当前主服务商</span> : null}
                    {provider.isDraft ? <span>未保存</span> : null}
                  </div>
                  <h3>{provider.baseUrl}</h3>
                </div>
              </div>
              <div className="management-tags">
                <span className="management-tag">{provider.modelCount} 个模型</span>
                <span className="management-tag">
                  {provider.hasMultimodal ? "包含多模态" : "文本优先"}
                </span>
                {provider.api ? <span className="management-tag">{provider.api}</span> : null}
              </div>
              <div className="inline-actions">
                <button
                  type="button"
                  className="action-button action-secondary"
                  onClick={() => openModelForm(provider.key)}
                >
                  新增模型
                </button>
                <button
                  type="button"
                  className="action-button action-secondary"
                  disabled={discoveringProvider === provider.key}
                  onClick={() => {
                    void discoverProviderModels(provider.key);
                  }}
                >
                  {discoveringProvider === provider.key ? "获取中..." : "获取模型"}
                </button>
                <button
                  type="button"
                  className="action-button action-danger"
                  onClick={() => removeProvider(provider.key)}
                >
                  删除服务商
                </button>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="deck-section">
        <header className="deck-section-header">
          <div>
            <h2>模型目录</h2>
            <p>切换默认模型，管理 allowlist 和 alias。</p>
          </div>
        </header>
        {showModelForm ? (
          <div className="control-form models-inline-form">
            <div className="models-form-grid">
              <label className="control-label">
                Model ID
                <input
                  value={modelForm.id}
                  onChange={(event) =>
                    setModelForm((prev) => ({ ...prev, id: event.target.value }))
                  }
                  placeholder="例如 qwen3.5-plus"
                />
              </label>
              <label className="control-label">
                名称
                <input
                  value={modelForm.name}
                  onChange={(event) =>
                    setModelForm((prev) => ({ ...prev, name: event.target.value }))
                  }
                  placeholder="可留空，默认使用 model id"
                />
              </label>
            </div>
            <div className="models-form-inline">
              <span className="action-feedback">服务商：{modelForm.provider}</span>
              <button
                type="button"
                className="action-button action-secondary"
                onClick={() => setShowModelAdvanced((value) => !value)}
              >
                {showModelAdvanced ? "收起更多配置" : "更多配置"}
              </button>
            </div>
            {showModelAdvanced ? (
              <div className="models-form-grid">
                <label className="control-label">
                  输入能力
                  <input
                    value={modelForm.input}
                    onChange={(event) =>
                      setModelForm((prev) => ({ ...prev, input: event.target.value }))
                    }
                    placeholder="text,image"
                  />
                </label>
                <label className="control-label">
                  上下文窗口
                  <input
                    value={modelForm.contextWindow}
                    onChange={(event) =>
                      setModelForm((prev) => ({ ...prev, contextWindow: event.target.value }))
                    }
                    placeholder="131072"
                  />
                </label>
                <label className="control-label">
                  最大输出
                  <input
                    value={modelForm.maxTokens}
                    onChange={(event) =>
                      setModelForm((prev) => ({ ...prev, maxTokens: event.target.value }))
                    }
                    placeholder="16384"
                  />
                </label>
                <label className="models-toggle models-toggle-card">
                  <input
                    type="checkbox"
                    checked={modelForm.reasoning}
                    onChange={(event) =>
                      setModelForm((prev) => ({ ...prev, reasoning: event.target.checked }))
                    }
                  />
                  <span>启用 Thinking</span>
                </label>
              </div>
            ) : null}
            {!showModelAdvanced ? (
              <span className="action-feedback">
                默认会用 `text`、`131072`、`16384`，需要时再展开更多配置。
              </span>
            ) : (
              <span className="action-feedback">
                输入能力：{inputPreview.length ? inputPreview.join(" / ") : "text"}
              </span>
            )}
            <div className="models-form-actions">
              <button
                type="button"
                className="action-button action-secondary"
                onClick={() => {
                  setShowModelForm(false);
                  setShowModelAdvanced(false);
                  setModelForm((prev) => ({
                    ...prev,
                    id: "",
                    name: "",
                    input: "text",
                    contextWindow: "",
                    maxTokens: "",
                    reasoning: false
                  }));
                }}
              >
                取消
              </button>
              <button type="button" className="action-button" onClick={addModelDraft}>
                加入本次更改
              </button>
            </div>
          </div>
        ) : null}
        {discoveredBatch ? (
          <div className="control-form models-inline-form">
            <div className="deck-section-header">
              <div>
                <h3>待导入模型</h3>
                <p>来源服务商：{discoveredBatch.provider}</p>
              </div>
            </div>
            <div className="inline-actions">
              <button
                type="button"
                className="action-button action-secondary"
                onClick={() =>
                  setDiscoveredBatch((prev) =>
                    prev
                      ? {
                          ...prev,
                          items: prev.items.map((item) => ({ ...item, selected: true }))
                        }
                      : prev
                  )
                }
              >
                全选
              </button>
              <button
                type="button"
                className="action-button action-secondary"
                onClick={() =>
                  setDiscoveredBatch((prev) =>
                    prev
                      ? {
                          ...prev,
                          items: prev.items.map((item) => ({ ...item, selected: false }))
                        }
                      : prev
                  )
                }
              >
                取消全选
              </button>
              <button type="button" className="action-button" onClick={importDiscoveredSelection}>
                加入本次更改
              </button>
            </div>
            <div className="models-discovery-list">
              {discoveredBatch.items.map((entry) => (
                <label key={entry.key} className="models-discovery-item">
                  <span className="models-toggle">
                    <input
                      type="checkbox"
                      checked={entry.selected}
                      onChange={(event) =>
                        setDiscoveredBatch((prev) =>
                          prev
                            ? {
                                ...prev,
                                items: prev.items.map((item) =>
                                  item.key === entry.key
                                    ? { ...item, selected: event.target.checked }
                                    : item
                                )
                              }
                            : prev
                        )
                      }
                    />
                    <span>{entry.name}</span>
                  </span>
                  <span className="models-table-key">{entry.key}</span>
                  <div className="management-tags">
                    <span className="management-tag">
                      {entry.mode === "overwrite" ? "将覆盖" : "将新增"}
                    </span>
                    <span className="management-tag">
                      {entry.input.length ? entry.input.join(" / ") : "text"}
                    </span>
                  </div>
                </label>
              ))}
            </div>
          </div>
        ) : null}
        <div className="models-toolbar">
          <label className="control-label models-primary-select">
            默认主模型
            <select value={primaryModel} onChange={(event) => setPrimaryModel(event.target.value)}>
              {items
                .filter((item) => item.allowed)
                .map((item) => (
                  <option key={item.key} value={item.key}>
                    {item.key}
                  </option>
                ))}
            </select>
          </label>
          <div className="models-save">
            {!primaryAllowed ? <span className="action-feedback">默认主模型必须保留在 allowlist 中。</span> : null}
            {message ? <span className="action-feedback">{message}</span> : null}
            <button
              type="button"
              className="action-button"
              disabled={pending || !hasChanges || !primaryAllowed}
              onClick={() => {
                startTransition(async () => {
                  setMessage("");
                  const response = await fetch("/api/models", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                      primaryModel,
                      models: items,
                      providerAdditions: providerDrafts,
                      modelAdditions: modelDrafts,
                      discoveredModels: importedDiscovered,
                      providerRemovals,
                      modelRemovals
                    })
                  });
                  const result = (await response.json()) as {
                    ok?: boolean;
                    error?: string;
                    restartSkipped?: boolean;
                    restartOk?: boolean;
                    restartStderr?: string;
                  };
                  if (response.ok && result.ok) {
                    let detail = `默认模型：${primaryModel}`;
                    let feedback: string;
                    let historyStatus: "success" | "error" = "success";

                    if (result.restartSkipped) {
                      feedback =
                        "模型配置已保存（未重启 Gateway，可能由环境变量跳过）";
                    } else if (result.restartOk) {
                      feedback = "模型配置已保存，Gateway 已重启";
                    } else {
                      const rs = result.restartStderr?.trim() || "未知错误";
                      feedback = `模型配置已保存，但 Gateway 重启失败：${rs}`;
                      detail = `${detail}；重启失败：${rs}`;
                      historyStatus = "error";
                    }

                    setMessage(feedback);
                    setProviderDrafts([]);
                    setModelDrafts([]);
                    setImportedDiscovered([]);
                    setDiscoveredBatch(null);
                    setProviderRemovals([]);
                    setModelRemovals([]);
                    pushActionHistory({
                      label: "保存模型配置",
                      status: historyStatus,
                      detail
                    });
                    router.refresh();
                    return;
                  }

                  const detail = result.error || "保存失败";
                  setMessage(detail);
                  pushActionHistory({
                    label: "保存模型配置",
                    status: "error",
                    detail
                  });
                });
              }}
            >
              {pending ? "保存中..." : "保存模型配置"}
            </button>
          </div>
        </div>
        <div className="models-table">
          {modelRows
            .filter((entry) => !providerRemovals.includes(entry.provider) && !modelRemovals.includes(entry.key))
            .map((entry) => {
            const current = items.find((item) => item.key === entry.key) ?? {
              key: entry.key,
              alias: entry.alias,
              allowed: entry.allowed
            };

            return (
              <article key={entry.key} className="models-table-row">
                <div className="models-table-main">
                  <div className="management-card-meta">
                    <span>{entry.provider}</span>
                    {entry.isPrimary ? <span>当前默认</span> : null}
                    {entry.isDraft ? <span>未保存</span> : null}
                    {entry.isImported ? <span>待导入</span> : null}
                  </div>
                  <h3>{entry.name}</h3>
                  <p className="models-table-key">{entry.key}</p>
                  <div className="management-tags">
                    <span className="management-tag">
                      上下文 {entry.contextWindow?.toLocaleString() ?? "未知"}
                    </span>
                    <span className="management-tag">
                      输出 {entry.maxTokens?.toLocaleString() ?? "未知"}
                    </span>
                    <span className="management-tag">
                      {entry.input.length ? entry.input.join(" / ") : "text"}
                    </span>
                  </div>
                </div>
                <div className="models-table-controls">
                  <label className="models-toggle">
                    <input
                      type="checkbox"
                      checked={current.allowed}
                      onChange={(event) => {
                        setItems((prev) =>
                          prev.map((item) =>
                            item.key === entry.key ? { ...item, allowed: event.target.checked } : item
                          )
                        );
                      }}
                    />
                    <span>允许使用</span>
                  </label>
                  <label className="control-label">
                    别名
                    <input
                      value={current.alias}
                      onChange={(event) => {
                        setItems((prev) =>
                          prev.map((item) =>
                            item.key === entry.key ? { ...item, alias: event.target.value } : item
                          )
                        );
                      }}
                      placeholder="可选别名"
                    />
                  </label>
                  <button
                    type="button"
                    className="action-button action-danger"
                    onClick={() => removeModel(entry.key)}
                  >
                    删除模型
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      </section>

      {model.authProfiles.length ? (
        <section className="deck-section">
          <header className="deck-section-header">
            <div>
              <h2>认证 Profile</h2>
              <p>当前配置中可见的认证档案摘要。</p>
            </div>
          </header>
          <div className="models-provider-grid">
            {model.authProfiles.map((profile) => (
              <article key={profile.key} className="management-card">
                <div className="management-card-meta">
                  <span>{profile.provider}</span>
                  <span>{profile.mode}</span>
                </div>
                <h3>{profile.key}</h3>
              </article>
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
