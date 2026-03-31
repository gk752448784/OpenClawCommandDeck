"use client";

export type ActionHistoryEntry = {
  id: string;
  label: string;
  status: "success" | "error";
  detail: string;
  createdAt: number;
};

const STORAGE_KEY = "openclaw-commanddeck-action-history";

function readHistory(): ActionHistoryEntry[] {
  if (typeof window === "undefined") {
    return [];
  }

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as ActionHistoryEntry[]) : [];
  } catch {
    return [];
  }
}

function writeHistory(entries: ActionHistoryEntry[]) {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(entries.slice(0, 12)));
  window.dispatchEvent(new CustomEvent("commanddeck:action-history-updated"));
}

export function pushActionHistory(entry: Omit<ActionHistoryEntry, "id" | "createdAt">) {
  const nextEntry: ActionHistoryEntry = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    createdAt: Date.now(),
    ...entry
  };
  writeHistory([nextEntry, ...readHistory()]);
}

export function getActionHistory() {
  return readHistory();
}
