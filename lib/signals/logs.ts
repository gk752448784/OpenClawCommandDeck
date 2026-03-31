import type { SessionsSnapshot } from "@/lib/adapters/sessions";

export type LogSignals = {
  excerpts: string[];
  tokens: string[];
  references: Array<{
    lineIndex: number;
    agentId: string | null;
    sessionKey: string | null;
    sessionId: string | null;
  }>;
  relatedSessionKeys: string[];
  relatedAgentIds: string[];
};

const AGENT_REF_RE = /\bagent=(?<agentId>[A-Za-z0-9._:-]+)\b/;
const SESSION_REF_RE = /\bsession=(?<sessionRef>[A-Za-z0-9._:-]+)\b/;
const TOKEN_RE = /[A-Za-z0-9._:-]+/g;
const MAX_TOKENS = 64;

function isNoisyToken(token: string): boolean {
  if (token.length < 2) {
    return true;
  }

  // Purely numeric fragments are high churn and low signal.
  if (/^\d+$/.test(token)) {
    return true;
  }

  // Date/time and ISO-like fragments are volatile.
  if (/^\d{4}[-/]\d{1,2}[-/]\d{1,2}$/i.test(token)) {
    return true;
  }
  if (/^\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?z?$/i.test(token)) {
    return true;
  }
  if (/^\d{4}-\d{2}-\d{2}t\d{2}:\d{2}:\d{2}(?:\.\d+)?z$/i.test(token)) {
    return true;
  }

  // UUID/hex-ish trace ids are unstable.
  if (/^[a-f0-9]{12,}$/i.test(token)) {
    return true;
  }
  if (
    /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(token)
  ) {
    return true;
  }

  return false;
}

function extractTokens(excerpts: string[]): string[] {
  const values = new Set<string>();
  for (const line of excerpts) {
    for (const match of line.matchAll(TOKEN_RE)) {
      const normalized = match[0].toLowerCase();
      if (!isNoisyToken(normalized)) {
        values.add(normalized);
      }
    }
  }
  return Array.from(values)
    .sort((left, right) => left.localeCompare(right))
    .slice(0, MAX_TOKENS);
}

export function collectLogSignals({
  logs,
  sessions,
  excerptLimit = 12
}: {
  logs: string[];
  sessions?: SessionsSnapshot;
  excerptLimit?: number;
}): LogSignals {
  const normalizedLogs = logs.map((line) => line.trim()).filter((line) => line.length > 0);
  const excerpts = normalizedLogs.slice(-Math.max(0, excerptLimit));
  const tokens = extractTokens(excerpts);
  const references: LogSignals["references"] = [];
  const relatedSessionKeys = new Set<string>();
  const relatedAgentIds = new Set<string>();
  const knownSessions = sessions?.sessions ?? [];
  const sessionByKey = new Map(knownSessions.map((session) => [session.key, session]));
  const sessionById = new Map(knownSessions.map((session) => [session.sessionId, session]));
  const knownAgents = new Set(knownSessions.map((session) => session.agentId));

  for (const [lineIndex, line] of excerpts.entries()) {
    const agentRef = AGENT_REF_RE.exec(line)?.groups?.agentId ?? null;
    const sessionRef = SESSION_REF_RE.exec(line)?.groups?.sessionRef ?? null;
    const sessionByRef = sessionRef
      ? sessionByKey.get(sessionRef) ?? sessionById.get(sessionRef)
      : undefined;
    const resolvedSessionKey = sessionByRef?.key ?? (sessionByKey.has(sessionRef ?? "") ? sessionRef : null);
    const resolvedSessionId = sessionByRef?.sessionId ?? (sessionById.has(sessionRef ?? "") ? sessionRef : null);

    if (agentRef || sessionRef) {
      references.push({
        lineIndex,
        agentId: agentRef,
        sessionKey: resolvedSessionKey,
        sessionId: resolvedSessionId
      });
    }

    if (agentRef && knownAgents.has(agentRef)) {
      relatedAgentIds.add(agentRef);
    }
    if (sessionByRef?.agentId) {
      relatedAgentIds.add(sessionByRef.agentId);
    }
    if (resolvedSessionKey) {
      relatedSessionKeys.add(resolvedSessionKey);
    }
  }

  return {
    excerpts,
    tokens,
    references,
    relatedSessionKeys: Array.from(relatedSessionKeys).sort((left, right) =>
      left.localeCompare(right)
    ),
    relatedAgentIds: Array.from(relatedAgentIds).sort((left, right) => left.localeCompare(right))
  };
}
