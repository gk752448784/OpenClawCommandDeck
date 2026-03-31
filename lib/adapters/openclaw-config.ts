import type { LoadResult } from "@/lib/types/raw";
import type { OpenClawConfig } from "@/lib/validators/openclaw-config";
import { parseOpenClawConfig } from "@/lib/validators/openclaw-config";
import { safeReadJsonFile } from "@/lib/server/safe-read";

export async function loadOpenClawConfig(
  path: string
): Promise<LoadResult<OpenClawConfig>> {
  const result = await safeReadJsonFile(path);
  if (!result.ok) {
    return result;
  }

  const parsed = parseOpenClawConfig(result.data);
  if (!parsed.success) {
    return {
      ok: false,
      error: {
        code: "invalid_shape",
        message: parsed.error.issues[0]?.message ?? "Invalid OpenClaw config"
      }
    };
  }

  return {
    ok: true,
    data: parsed.data
  };
}

export function redactConfigForDashboard(config: OpenClawConfig): OpenClawConfig {
  const copy = structuredClone(config);

  if (copy.gateway.auth.token) {
    copy.gateway.auth.token = "[redacted]";
  }

  if (copy.channels.feishu?.appSecret) {
    copy.channels.feishu.appSecret = "[redacted]";
  }

  for (const provider of Object.values(copy.models.providers)) {
    if (provider.apiKey) {
      provider.apiKey = "[redacted]";
    }
  }

  return copy;
}
