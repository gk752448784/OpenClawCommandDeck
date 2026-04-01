import {
  parseOpenClawJsonOutput,
  tryRunOpenClawCli
} from "@/lib/server/openclaw-cli";

type RuntimeStatusPayload = {
  runtimeVersion?: string;
  gateway?: {
    reachable?: boolean;
    error?: string | null;
  };
};

export type ServiceRuntimeSnapshot = {
  version: string;
  gateway: {
    reachable: "reachable" | "unreachable" | "unknown";
    error: string | null;
  };
  checkedAt: string;
};

export async function loadServiceRuntime(): Promise<ServiceRuntimeSnapshot> {
  const checkedAt = new Date().toISOString();
  const statusResult = await tryRunOpenClawCli(["status", "--json"]);
  if (!statusResult.ok) {
    return {
      version: "unknown",
      gateway: {
        reachable: "unknown",
        error: statusResult.stderr || null
      },
      checkedAt
    };
  }

  try {
    const parsed = parseOpenClawJsonOutput<RuntimeStatusPayload>(statusResult.stdout);
    return {
      version: parsed.runtimeVersion ?? "unknown",
      gateway: {
        reachable:
          parsed.gateway?.reachable === true
            ? "reachable"
            : parsed.gateway?.reachable === false
              ? "unreachable"
              : "unknown",
        error: parsed.gateway?.error ?? null
      },
      checkedAt
    };
  } catch {
    return {
      version: "unknown",
      gateway: {
        reachable: "unknown",
        error: "无法解析 openclaw status 输出"
      },
      checkedAt
    };
  }
}
