import type { SessionsSnapshot } from "@/lib/adapters/sessions";
import type { OpenClawConfig } from "@/lib/validators/openclaw-config";

export type ModelSignals = {
  primaryModelKey: string;
  candidateModelKeys: string[];
};

export function collectModelSignals({
  config,
  sessions
}: {
  config: OpenClawConfig;
  sessions?: SessionsSnapshot;
}): ModelSignals {
  const candidates = new Set<string>();
  const primaryModelKey = config.agents.defaults.model.primary.trim();

  for (const provider of Object.values(config.models.providers)) {
    for (const model of provider.models ?? []) {
      const modelKey = model.id.trim();
      if (modelKey) {
        candidates.add(modelKey);
      }
    }
  }

  for (const session of sessions?.sessions ?? []) {
    const sessionModel = session.model?.trim();
    if (sessionModel) {
      candidates.add(sessionModel);
    }
  }

  return {
    primaryModelKey,
    candidateModelKeys: Array.from(candidates).sort((left, right) => left.localeCompare(right))
  };
}
