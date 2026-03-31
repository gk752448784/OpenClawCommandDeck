import { describe, expect, it } from "vitest";

import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";
import { buildModelsDashboardModel } from "@/lib/selectors/models-dashboard";
import { OPENCLAW_FIXTURE_ROOT } from "@/tests/unit/helpers/openclaw-fixture";

describe("models dashboard selector", () => {
  it("builds provider and model catalog data from the fixture config", async () => {
    const configResult = await loadOpenClawConfig(`${OPENCLAW_FIXTURE_ROOT}/openclaw.json`);

    expect(configResult.ok).toBe(true);

    if (!configResult.ok) {
      throw new Error("expected openclaw config to load");
    }

    const model = buildModelsDashboardModel(configResult.data);

    expect(model.primaryModel.key).toBe("openai/gpt-5.3-codex");
    expect(model.providers.some((provider) => provider.key === "openai")).toBe(true);
    expect(model.providers).toHaveLength(1);
    expect(model.providers.some((provider) => provider.key === "bailian")).toBe(false);
    expect(model.providers.find((provider) => provider.key === "openai")?.isPrimaryProvider).toBe(
      true
    );
    expect(model.authProfiles[0]?.key).toBe("openai-codex:default");
    expect(model.models.some((entry) => entry.key === "openai/gpt-5.3-codex")).toBe(true);
    expect(model.models.find((entry) => entry.key === "openai/gpt-5.3-codex")?.alias).toBe(
      "OpenAI Gateway 5.3"
    );
    expect(model.models.some((entry) => entry.key === "bailian/qwen3.5-plus")).toBe(false);
    expect(model.models.every((entry) => entry.provider === "openai")).toBe(true);
  });
});
