import { NextResponse } from "next/server";

import { loadSkillDetails } from "@/lib/server/skills";

export async function GET(
  _request: Request,
  context: { params: Promise<{ skillName: string }> }
) {
  const { skillName } = await context.params;

  try {
    const data = await loadSkillDetails(decodeURIComponent(skillName));
    return NextResponse.json(data);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Skill details unavailable";
    const status = /not found/i.test(message) ? 404 : 500;

    return NextResponse.json({ ok: false, error: message }, { status });
  }
}
