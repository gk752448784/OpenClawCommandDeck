import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { CliCommand } from "@/lib/control/commands";

const execFileAsync = promisify(execFile);
const DEFAULT_CONTROL_TIMEOUT_MS = Number(process.env.OPENCLAW_CONTROL_TIMEOUT_MS ?? "15000");

export type ControlResult = {
  ok: boolean;
  stdout: string;
  stderr: string;
  errorCode?: "cli_timeout" | "cli_spawn_error" | "cli_unknown_error";
};

export async function executeCliCommand(
  input: CliCommand
): Promise<ControlResult> {
  try {
    const { stdout, stderr } = await execFileAsync(input.command, input.args, {
      env: process.env,
      maxBuffer: 1024 * 1024,
      timeout: DEFAULT_CONTROL_TIMEOUT_MS
    });

    return {
      ok: true,
      stdout,
      stderr
    };
  } catch (error) {
    const timeoutError =
      typeof error === "object" &&
      error !== null &&
      "killed" in error &&
      Boolean(error.killed) &&
      "signal" in error &&
      error.signal === "SIGTERM";
    const errorCode = timeoutError
      ? "cli_timeout"
      : typeof error === "object" && error !== null && "code" in error
        ? "cli_spawn_error"
        : "cli_unknown_error";
    const stderr =
      typeof error === "object" && error !== null && "stderr" in error
        ? String(error.stderr)
        : error instanceof Error
          ? error.message
          : "Unknown CLI error";
    const stdout =
      typeof error === "object" && error !== null && "stdout" in error
        ? String(error.stdout)
        : "";

    return {
      ok: false,
      stdout,
      stderr,
      errorCode
    };
  }
}
