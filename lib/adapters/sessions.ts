import path from "node:path";

import { safeReadJsonFile } from "@/lib/server/safe-read";
import type { LoadResult } from "@/lib/types/raw";

export type SessionStoreEntry = {
  sessionId?: string;
  updatedAt?: number;
  key?: string;
  model?: string;
  kind?: string;
  contextTokens?: number;
  percentUsed?: number | null;
};

export type LoadedSession = {
  sessionId: string;
  key: string;
  updatedAt?: number;
  ageMs?: number;
  model?: string;
  kind?: string;
  contextTokens?: number;
  percentUsed?: number | null;
  agentId: string;
};

export type SessionsSnapshot = {
  count: number;
  sessions: LoadedSession[];
};

function parseSessionMap(
  agentId: string,
  data: unknown
): LoadedSession[] {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return [];
  }

  const now = Date.now();
  return Object.entries(data as Record<string, SessionStoreEntry>).map(([key, value]) => ({
    sessionId: value.sessionId ?? key,
    key,
    updatedAt: value.updatedAt,
    ageMs: typeof value.updatedAt === "number" ? Math.max(0, now - value.updatedAt) : undefined,
    model: value.model,
    kind: value.kind,
    contextTokens: value.contextTokens,
    percentUsed: value.percentUsed,
    agentId
  }));
}

export async function loadSessionsSnapshot(
  openClawRoot: string,
  agentIds: string[]
): Promise<LoadResult<SessionsSnapshot>> {
  const results = await Promise.all(
    agentIds.map(async (agentId) => {
      const result = await safeReadJsonFile<unknown>(
        path.join(openClawRoot, "agents", agentId, "sessions", "sessions.json")
      );

      if (!result.ok) {
        if (result.error.code === "missing_file") {
          return [] satisfies LoadedSession[];
        }
        throw new Error(result.error.message);
      }

      return parseSessionMap(agentId, result.data);
    })
  );

  const sessions = results
    .flat()
    .sort((left, right) => (right.updatedAt ?? 0) - (left.updatedAt ?? 0));

  return {
    ok: true,
    data: {
      count: sessions.length,
      sessions
    }
  };
}
