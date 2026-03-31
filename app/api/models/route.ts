import path from "node:path";
import { writeFile } from "node:fs/promises";

import { NextRequest, NextResponse } from "next/server";

import { OPENCLAW_ROOT } from "@/lib/config";
import { restartGatewayAfterModelChange } from "@/lib/control/restart-gateway";
import { safeReadJsonFile } from "@/lib/server/safe-read";

type ModelDraft = {
  key: string;
  alias: string;
  allowed: boolean;
};

type ProviderAddition = {
  key: string;
  baseUrl: string;
  api?: string;
  apiKey?: string;
};

type ModelAddition = {
  provider: string;
  id: string;
  name?: string;
  input?: string[];
  contextWindow?: number;
  maxTokens?: number;
  reasoning?: boolean;
};

type DiscoveredModel = {
  provider: string;
  id: string;
  name?: string;
  input?: string[];
  contextWindow?: number | null;
  maxTokens?: number | null;
  thinking?: boolean;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export async function GET() {
  const configPath = path.join(OPENCLAW_ROOT, "openclaw.json");
  const result = await safeReadJsonFile<Record<string, unknown>>(configPath);

  if (!result.ok) {
    return NextResponse.json(result, { status: 500 });
  }

  return NextResponse.json(result.data);
}

export async function POST(request: NextRequest) {
  const configPath = path.join(OPENCLAW_ROOT, "openclaw.json");
  const result = await safeReadJsonFile<Record<string, unknown>>(configPath);

  if (!result.ok) {
    return NextResponse.json(result, { status: 500 });
  }

  const body = (await request.json()) as {
    primaryModel?: string;
    models?: ModelDraft[];
    providerAdditions?: ProviderAddition[];
    modelAdditions?: ModelAddition[];
    discoveredModels?: DiscoveredModel[];
    providerRemovals?: string[];
    modelRemovals?: string[];
  };

  if (!body.primaryModel || !Array.isArray(body.models)) {
    return NextResponse.json({ ok: false, error: "无效的模型配置负载" }, { status: 400 });
  }

  const raw = result.data as Record<string, unknown>;
  const rawModels = isRecord(raw.models) ? raw.models : {};
  const providers = isRecord(rawModels.providers) ? rawModels.providers : {};
  const providerAdditions = Array.isArray(body.providerAdditions) ? body.providerAdditions : [];
  const modelAdditions = Array.isArray(body.modelAdditions) ? body.modelAdditions : [];
  const discoveredModels = Array.isArray(body.discoveredModels) ? body.discoveredModels : [];
  const providerRemovals = new Set(
    Array.isArray(body.providerRemovals) ? body.providerRemovals.map((item) => item.trim()) : []
  );
  const modelRemovals = new Set(
    Array.isArray(body.modelRemovals) ? body.modelRemovals.map((item) => item.trim()) : []
  );
  const nextProviders: Record<string, unknown> = { ...providers };

  if (modelRemovals.has(body.primaryModel)) {
    return NextResponse.json({ ok: false, error: "默认主模型不能被删除" }, { status: 400 });
  }

  for (const key of providerRemovals) {
    if (!key) {
      continue;
    }
    delete nextProviders[key];
  }

  for (const provider of providerAdditions) {
    const key = provider.key?.trim();
    const baseUrl = provider.baseUrl?.trim();

    if (!key || !baseUrl) {
      return NextResponse.json({ ok: false, error: "新增服务商缺少必填字段" }, { status: 400 });
    }

    if (key in nextProviders) {
      return NextResponse.json({ ok: false, error: `服务商 ${key} 已存在` }, { status: 400 });
    }

    nextProviders[key] = {
      baseUrl,
      api: provider.api?.trim() || "openai-completions",
      ...(provider.apiKey?.trim() ? { apiKey: provider.apiKey.trim() } : {}),
      models: []
    };
  }

  for (const addition of modelAdditions) {
    const providerKey = addition.provider?.trim();
    const id = addition.id?.trim();

    if (!providerKey || !id) {
      return NextResponse.json({ ok: false, error: "新增模型缺少必填字段" }, { status: 400 });
    }

    const providerValue = nextProviders[providerKey];

    if (!isRecord(providerValue)) {
      return NextResponse.json(
        { ok: false, error: `新增模型引用了不存在的 provider：${providerKey}` },
        { status: 400 }
      );
    }

    const existingModels = Array.isArray(providerValue.models) ? providerValue.models : [];

    if (
      existingModels.some((item) => isRecord(item) && typeof item.id === "string" && item.id === id)
    ) {
      return NextResponse.json(
        { ok: false, error: `模型 ${providerKey}/${id} 已存在` },
        { status: 400 }
      );
    }

    providerValue.models = [
      ...existingModels,
      {
        id,
        ...(addition.name?.trim() ? { name: addition.name.trim() } : {}),
        input: Array.isArray(addition.input)
          ? addition.input.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim())
          : ["text"],
        ...(typeof addition.contextWindow === "number" ? { contextWindow: addition.contextWindow } : {}),
        ...(typeof addition.maxTokens === "number" ? { maxTokens: addition.maxTokens } : {}),
        ...(typeof addition.reasoning === "boolean" ? { reasoning: addition.reasoning } : {})
      }
    ];
  }

  for (const discovered of discoveredModels) {
    const providerKey = discovered.provider?.trim();
    const id = discovered.id?.trim();

    if (!providerKey || !id) {
      continue;
    }

    const providerValue = nextProviders[providerKey];

    if (!isRecord(providerValue)) {
      continue;
    }

    const existingModels = Array.isArray(providerValue.models) ? providerValue.models : [];
    const normalized = {
      id,
      ...(discovered.name?.trim() ? { name: discovered.name.trim() } : {}),
      input: Array.isArray(discovered.input)
        ? discovered.input
            .filter((item) => typeof item === "string" && item.trim())
            .map((item) => item.trim())
        : ["text"],
      ...(typeof discovered.contextWindow === "number" ? { contextWindow: discovered.contextWindow } : {}),
      ...(typeof discovered.maxTokens === "number" ? { maxTokens: discovered.maxTokens } : {}),
      ...(typeof discovered.thinking === "boolean" ? { reasoning: discovered.thinking } : {})
    };

    const nextList = [...existingModels];
    const index = nextList.findIndex(
      (item) => isRecord(item) && typeof item.id === "string" && item.id === id
    );

    if (index >= 0) {
      nextList[index] = normalized;
    } else {
      nextList.push(normalized);
    }

    providerValue.models = nextList;
  }

  for (const [providerKey, providerValue] of Object.entries(nextProviders)) {
    if (!isRecord(providerValue) || !Array.isArray(providerValue.models)) {
      continue;
    }

    providerValue.models = providerValue.models.filter((model) => {
      if (!isRecord(model) || typeof model.id !== "string") {
        return true;
      }

      return !modelRemovals.has(`${providerKey}/${model.id}`);
    });
  }

  for (const key of providerRemovals) {
    if (!key) {
      continue;
    }

    if (key === body.primaryModel.split("/")[0]) {
      return NextResponse.json({ ok: false, error: "默认主模型所在服务商不能被删除" }, { status: 400 });
    }
  }

  const validKeys = new Set<string>();

  for (const [providerKey, providerValue] of Object.entries(nextProviders)) {
    if (!isRecord(providerValue) || !Array.isArray(providerValue.models)) {
      continue;
    }

    for (const model of providerValue.models) {
      if (isRecord(model) && typeof model.id === "string") {
        validKeys.add(`${providerKey}/${model.id}`);
      }
    }
  }

  if (!validKeys.has(body.primaryModel)) {
    return NextResponse.json({ ok: false, error: "默认主模型不在模型目录中" }, { status: 400 });
  }

  const allowedKeys = new Set(body.models.filter((item) => item.allowed).map((item) => item.key));

  if (!allowedKeys.has(body.primaryModel)) {
    return NextResponse.json(
      { ok: false, error: "默认主模型必须保留在 allowlist 中" },
      { status: 400 }
    );
  }

  const rawAgents = isRecord(raw.agents) ? raw.agents : {};
  const rawDefaults = isRecord(rawAgents.defaults) ? rawAgents.defaults : {};
  const existingModels = isRecord(rawDefaults.models) ? rawDefaults.models : {};

  const nextModels: Record<string, unknown> = {};

  for (const item of body.models) {
    if (modelRemovals.has(item.key) || !item.allowed || !validKeys.has(item.key)) {
      continue;
    }

    const existingEntry = isRecord(existingModels[item.key])
      ? (existingModels[item.key] as Record<string, unknown>)
      : {};
    const nextEntry: Record<string, unknown> = { ...existingEntry };

    if (item.alias.trim()) {
      nextEntry.alias = item.alias.trim();
    } else {
      delete nextEntry.alias;
    }

    nextModels[item.key] = nextEntry;
  }

  raw.agents = {
    ...rawAgents,
    defaults: {
      ...rawDefaults,
      model: {
        ...(isRecord(rawDefaults.model) ? rawDefaults.model : {}),
        primary: body.primaryModel
      },
      models: nextModels
    }
  };
  raw.models = {
    ...rawModels,
    providers: nextProviders
  };

  await writeFile(configPath, `${JSON.stringify(raw, null, 2)}\n`, "utf8");

  const restart = await restartGatewayAfterModelChange();
  const payload = restart.ran
    ? {
        ok: true as const,
        restartOk: restart.ok,
        restartStderr: restart.stderr
      }
    : { ok: true as const, restartSkipped: true as const };

  return NextResponse.json(payload);
}
