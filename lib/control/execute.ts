import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { CliCommand } from "@/lib/control/commands";

const execFileAsync = promisify(execFile);

export type ControlResult = {
  ok: boolean;
  stdout: string;
  stderr: string;
};

export async function executeCliCommand(
  input: CliCommand
): Promise<ControlResult> {
  try {
    const { stdout, stderr } = await execFileAsync(input.command, input.args, {
      env: process.env,
      maxBuffer: 1024 * 1024
    });

    return {
      ok: true,
      stdout,
      stderr
    };
  } catch (error) {
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
      stderr
    };
  }
}
