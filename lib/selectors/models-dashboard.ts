import type { OpenClawConfig } from "@/lib/validators/openclaw-config";

export type ModelsDashboardModel = {
  primaryModel: {
    key: string;
    alias: string;
    provider: string;
    name: string;
    contextWindow: number | null;
    maxTokens: number | null;
    input: string[];
    reasoning: boolean;
  };
  providers: Array<{
    key: string;
    baseUrl: string;
    api: string;
    modelCount: number;
    isPrimaryProvider: boolean;
    hasMultimodal: boolean;
  }>;
  authProfiles: Array<{
    key: string;
    provider: string;
    mode: string;
  }>;
  models: Array<{
    key: string;
    provider: string;
    id: string;
    name: string;
    alias: string;
    allowed: boolean;
    isPrimary: boolean;
    contextWindow: number | null;
    maxTokens: number | null;
    input: string[];
    reasoning: boolean;
  }>;
};

function getAlias(config: OpenClawConfig, key: string) {
  const entry = config.agents.defaults.models[key];
  if (entry && typeof entry === "object" && entry !== null && "alias" in entry) {
    return typeof entry.alias === "string" ? entry.alias : "";
  }
  return "";
}

export function buildModelsDashboardModel(config: OpenClawConfig): ModelsDashboardModel {
  const primaryKey = config.agents.defaults.model.primary;
  const [primaryProvider] = primaryKey.split("/");

  const models = Object.entries(config.models.providers)
    .flatMap(([providerKey, provider]) =>
      (provider.models ?? []).map((model) => {
        const key = `${providerKey}/${model.id}`;

        return {
          key,
          provider: providerKey,
          id: model.id,
          name: model.name ?? model.id,
          alias: getAlias(config, key),
          allowed: key in config.agents.defaults.models,
          isPrimary: key === primaryKey,
          contextWindow: model.contextWindow ?? null,
          maxTokens: model.maxTokens ?? null,
          input: model.input ?? [],
          reasoning: model.reasoning ?? false
        };
      })
    )
    .sort((left, right) => {
      if (left.isPrimary !== right.isPrimary) {
        return left.isPrimary ? -1 : 1;
      }

      if (left.allowed !== right.allowed) {
        return left.allowed ? -1 : 1;
      }

      return left.key.localeCompare(right.key);
    });

  const primaryModel =
    models.find((model) => model.key === primaryKey) ??
    ({
      key: primaryKey,
      alias: getAlias(config, primaryKey),
      provider: primaryProvider,
      name: primaryKey.split("/").slice(1).join("/"),
      contextWindow: null,
      maxTokens: null,
      input: [],
      reasoning: false
    } as ModelsDashboardModel["primaryModel"]);

  return {
    primaryModel,
    providers: Object.entries(config.models.providers).map(([providerKey, provider]) => ({
      key: providerKey,
      baseUrl: provider.baseUrl ?? "未配置",
      api: provider.api ?? "openai-completions",
      modelCount: provider.models?.length ?? 0,
      isPrimaryProvider: providerKey === primaryProvider,
      hasMultimodal: (provider.models ?? []).some((model) => (model.input ?? []).includes("image"))
    })),
    authProfiles: Object.entries(config.auth?.profiles ?? {}).map(([key, profile]) => ({
      key,
      provider: profile.provider ?? "unknown",
      mode: profile.mode ?? "unknown"
    })),
    models
  };
}
