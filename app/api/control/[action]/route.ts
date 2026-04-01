import { NextRequest, NextResponse } from "next/server";

import {
  buildDispatchAgentCommand,
  buildFixCronTargetCommand,
  buildRunCronCommand,
  buildSwitchModelCommand,
  buildToggleChannelCommand,
  buildTogglePluginCommand,
  buildToggleCronCommand
} from "@/lib/control/commands";
import { executeCliCommand } from "@/lib/control/execute";
import { restartGatewayAfterModelChange } from "@/lib/control/restart-gateway";

type ActionBody = Record<string, unknown>;

function requireString(body: ActionBody, key: string) {
  const value = body[key];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing string field: ${key}`);
  }
  return value;
}

function requireBoolean(body: ActionBody, key: string) {
  const value = body[key];
  if (typeof value !== "boolean") {
    throw new Error(`Missing boolean field: ${key}`);
  }
  return value;
}

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ action: string }> }
) {
  const { action } = await context.params;
  const body = (await request.json()) as ActionBody;

  let result;

  switch (action) {
    case "toggle-cron":
      result = await executeCliCommand(
        buildToggleCronCommand(
          requireString(body, "id"),
          requireBoolean(body, "enabled")
        )
      );
      break;
    case "run-cron":
      result = await executeCliCommand(buildRunCronCommand(requireString(body, "id")));
      break;
    case "fix-cron-target":
      result = await executeCliCommand(
        buildFixCronTargetCommand(
          requireString(body, "id"),
          requireString(body, "channel"),
          requireString(body, "target")
        )
      );
      break;
    case "toggle-channel":
      result = await executeCliCommand(
        buildToggleChannelCommand(
          requireString(body, "channelId"),
          requireBoolean(body, "enabled")
        )
      );
      break;
    case "toggle-plugin":
      result = await executeCliCommand(
        buildTogglePluginCommand(
          requireString(body, "pluginId"),
          requireBoolean(body, "enabled")
        )
      );
      break;
    case "switch-model": {
      const setResult = await executeCliCommand(
        buildSwitchModelCommand(requireString(body, "model"))
      );
      if (!setResult.ok) {
        result = setResult;
        break;
      }
      const restart = await restartGatewayAfterModelChange();
      result = restart.ran
        ? {
            ...setResult,
            restartOk: restart.ok,
            restartStdout: restart.stdout,
            restartStderr: restart.stderr
          }
        : { ...setResult, restartSkipped: true };
      break;
    }
    case "dispatch-agent":
      result = await executeCliCommand(
        buildDispatchAgentCommand(
          requireString(body, "agentId"),
          requireString(body, "message")
        )
      );
      break;
    default:
      return NextResponse.json(
        { ok: false, error: `Unsupported action: ${action}` },
        { status: 404 }
      );
  }

  return NextResponse.json(result, {
    status: result.ok ? 200 : result.errorCode === "cli_timeout" ? 504 : 500
  });
}
