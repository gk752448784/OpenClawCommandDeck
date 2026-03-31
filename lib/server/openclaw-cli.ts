import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export function extractJsonPayload(raw: string) {
  const firstObject = raw.indexOf("{");
  const firstArray = raw.indexOf("[{");
  const startCandidates = [firstObject, firstArray].filter((value) => value >= 0);

  if (startCandidates.length === 0) {
    throw new Error("未找到 JSON 输出");
  }

  const start = Math.min(...startCandidates);
  const opening = raw[start];
  const closing = opening === "[" ? "]" : "}";
  let depth = 0;
  let inString = false;
  let escaping = false;

  for (let index = start; index < raw.length; index += 1) {
    const char = raw[index];

    if (inString) {
      if (escaping) {
        escaping = false;
        continue;
      }

      if (char === "\\") {
        escaping = true;
        continue;
      }

      if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") {
      inString = true;
      continue;
    }

    if (char === opening) {
      depth += 1;
      continue;
    }

    if (char === closing) {
      depth -= 1;
      if (depth === 0) {
        return raw.slice(start, index + 1);
      }
    }
  }

  throw new Error("JSON 输出不完整");
}

export function parseOpenClawJsonOutput<T>(raw: string): T {
  return JSON.parse(extractJsonPayload(raw)) as T;
}

export function summarizeLogLines(raw: string) {
  return raw
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => /^\d{4}-\d{2}-\d{2}T/.test(line));
}

export async function runOpenClawCli(args: string[]) {
  const { stdout, stderr } = await execFileAsync("openclaw", args, {
    env: process.env,
    maxBuffer: 1024 * 1024 * 4
  });

  return {
    stdout,
    stderr
  };
}

export async function tryRunOpenClawCli(args: string[]) {
  try {
    const result = await runOpenClawCli(args);
    return {
      ok: true as const,
      ...result
    };
  } catch (error) {
    return {
      ok: false as const,
      stdout:
        typeof error === "object" && error !== null && "stdout" in error
          ? String(error.stdout)
          : "",
      stderr:
        typeof error === "object" && error !== null && "stderr" in error
          ? String(error.stderr)
          : error instanceof Error
            ? error.message
            : "Unknown CLI error"
    };
  }
}
