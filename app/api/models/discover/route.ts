import path from "node:path";

import { NextRequest, NextResponse } from "next/server";

import { OPENCLAW_ROOT } from "@/lib/config";
import { safeReadJsonFile } from "@/lib/server/safe-read";

type DiscoverResponseModel = {
  provider: string;
  id: string;
  name: string;
  input: string[];
  contextWindow: number | null;
  maxTokens: number | null;
  thinking: boolean;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function asPositiveNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function normalizeModel(provider: string, item: unknown): DiscoverResponseModel | null {
  if (!isRecord(item) || typeof item.id !== "string") {
    return null;
  }

  const capabilities = isRecord(item.capabilities) ? item.capabilities : {};
  const supportsImage =
    (typeof capabilities.vision === "boolean" && capabilities.vision) ||
    (Array.isArray(item.input_modalities) && item.input_modalities.includes("image"));
  const thinking =
    (typeof capabilities.reasoning === "boolean" && capabilities.reasoning) ||
    (typeof item.reasoning === "boolean" && item.reasoning);

  return {
    provider,
    id: item.id,
    name: typeof item.name === "string" && item.name.trim() ? item.name : item.id,
    input: supportsImage ? ["text", "image"] : ["text"],
    contextWindow:
      asPositiveNumber(item.contextWindow) ?? asPositiveNumber(item.context_window),
    maxTokens:
      asPositiveNumber(item.maxTokens) ??
      asPositiveNumber(item.max_output_tokens) ??
      asPositiveNumber(item.max_completion_tokens),
    thinking
  };
}

export async function POST(request: NextRequest) {
  const body = (await request.json()) as {
    providerKey?: string;
    baseUrl?: string;
    apiType?: string;
    apiKey?: string;
  };

  const providerKey = body.providerKey?.trim();
  let baseUrl = body.baseUrl?.trim();
  let apiType = body.apiType?.trim();
  let apiKey = body.apiKey?.trim();

  if (providerKey && (!baseUrl || !apiKey)) {
    const configPath = path.join(OPENCLAW_ROOT, "openclaw.json");
    const result = await safeReadJsonFile<Record<string, unknown>>(configPath);

    if (result.ok) {
      const raw = result.data as Record<string, unknown>;
      const provider =
        isRecord(raw.models) &&
        isRecord(raw.models.providers) &&
        isRecord(raw.models.providers[providerKey])
          ? raw.models.providers[providerKey]
          : null;

      if (provider) {
        baseUrl = baseUrl || (typeof provider.baseUrl === "string" ? provider.baseUrl : "");
        apiType = apiType || (typeof provider.api === "string" ? provider.api : "");
        apiKey = apiKey || (typeof provider.apiKey === "string" ? provider.apiKey : "");
      }
    }
  }

  if (!providerKey || !baseUrl || !apiKey) {
    return NextResponse.json(
      { ok: false, error: "该服务商缺少请求远端模型所需的配置" },
      { status: 400 }
    );
  }

  if (apiType !== "openai-completions") {
    return NextResponse.json(
      { ok: false, error: "当前只支持 openai-completions 类型自动获取" },
      { status: 400 }
    );
  }

  const endpoint = `${baseUrl.replace(/\/+$/, "")}/models`;

  try {
    const response = await fetch(endpoint, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${apiKey}`
      },
      cache: "no-store"
    });

    if (!response.ok) {
      return NextResponse.json(
        { ok: false, error: `获取模型失败：${response.status} ${response.statusText}`.trim() },
        { status: response.status || 502 }
      );
    }

    const payload = (await response.json()) as { data?: unknown };

    if (!isRecord(payload) || !Array.isArray(payload.data)) {
      return NextResponse.json(
        { ok: false, error: "该服务商返回的模型列表格式暂不支持" },
        { status: 400 }
      );
    }

    const models = payload.data
      .map((item) => normalizeModel(providerKey, item))
      .filter((item): item is DiscoverResponseModel => item !== null);

    return NextResponse.json({ ok: true, models });
  } catch (error) {
    const detail = error instanceof Error ? error.message : "未知错误";
    return NextResponse.json({ ok: false, error: `获取模型失败：${detail}` }, { status: 502 });
  }
}
