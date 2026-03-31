import path from "node:path";
import { NextResponse } from "next/server";

import { OPENCLAW_ROOT } from "@/lib/config";
import { loadOpenClawConfig } from "@/lib/adapters/openclaw-config";

export async function GET() {
  const configResult = await loadOpenClawConfig(path.join(OPENCLAW_ROOT, "openclaw.json"));
  if (!configResult.ok) {
    return NextResponse.json(configResult, { status: 500 });
  }

  return NextResponse.json({
    primaryModel: configResult.data.agents.defaults.model.primary,
    availableModels: Object.keys(configResult.data.agents.defaults.models),
    workspace: configResult.data.agents.defaults.workspace
  });
}
