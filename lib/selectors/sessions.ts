import type { SessionItemModel, SessionsModel } from "@/lib/types/view-models";

type RawSession = {
  sessionId: string;
  key: string;
  updatedAt?: number;
  ageMs?: number | null;
  model?: string | null;
  contextTokens?: number | null;
  agentId: string;
  kind?: string | null;
  percentUsed?: number | null;
};

type RawSessionsPayload = {
  count: number;
  sessions: RawSession[];
};

function formatAge(ageMs?: number | null) {
  if (ageMs == null) {
    return "未知";
  }

  const minutes = Math.round(ageMs / 60000);
  if (minutes < 1) {
    return "刚刚";
  }
  if (minutes < 60) {
    return `${minutes} 分钟前`;
  }

  const hours = Math.round(minutes / 60);
  if (hours < 24) {
    return `${hours} 小时前`;
  }

  const days = Math.round(hours / 24);
  return `${days} 天前`;
}

function inferChannel(key: string) {
  const parts = key.split(":");
  return parts[2] ?? "direct";
}

function toSessionItem(session: RawSession): SessionItemModel {
  return {
    id: session.sessionId,
    agentId: session.agentId,
    channel: inferChannel(session.key),
    kind: session.kind ?? "direct",
    model: session.model ?? "未知模型",
    ageLabel: formatAge(session.ageMs),
    percentUsed:
      typeof session.percentUsed === "number" ? `${session.percentUsed}%` : "未采样",
    status: (session.ageMs ?? Number.MAX_SAFE_INTEGER) < 5 * 60 * 1000 ? "active" : "waiting"
  };
}

export function buildSessionsModel(payload: RawSessionsPayload): SessionsModel {
  const items = payload.sessions.slice(0, 8).map(toSessionItem);
  const activeCount = items.filter((item) => item.status === "active").length;

  return {
    total: payload.count,
    activeSummary: `${activeCount}/${items.length || 0} 活跃`,
    items
  };
}
