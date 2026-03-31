import { readFile } from "node:fs/promises";

import type { LoadError, LoadResult } from "@/lib/types/raw";

function buildReadError(error: unknown): LoadError {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  ) {
    return {
      code: "missing_file",
      message: "File does not exist"
    };
  }

  return {
    code: "read_error",
    message: error instanceof Error ? error.message : "Unknown read error"
  };
}

export async function safeReadTextFile(path: string): Promise<LoadResult<string>> {
  try {
    const data = await readFile(path, "utf8");
    return { ok: true, data };
  } catch (error) {
    return {
      ok: false,
      error: buildReadError(error)
    };
  }
}

export async function safeReadJsonFile<T>(
  path: string
): Promise<LoadResult<unknown>> {
  const textResult = await safeReadTextFile(path);
  if (!textResult.ok) {
    return textResult;
  }

  try {
    return {
      ok: true,
      data: JSON.parse(textResult.data) as T
    };
  } catch (error) {
    return {
      ok: false,
      error: {
        code: "invalid_json",
        message: error instanceof Error ? error.message : "Invalid JSON"
      }
    };
  }
}
