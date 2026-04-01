import {
  parseOpenClawJsonOutput,
  tryRunOpenClawCli
} from "@/lib/server/openclaw-cli";

const SKILLS_TTL_MS = 60_000;

export type SkillMissing = {
  bins: string[];
  anyBins: string[];
  env: string[];
  config: string[];
  os: string[];
};

export type SkillInstallHint = {
  id: string;
  kind: string;
  label: string;
  bins: string[];
};

export type SkillListEntry = {
  name: string;
  description: string;
  emoji?: string;
  eligible: boolean;
  disabled: boolean;
  blockedByAllowlist: boolean;
  source: string;
  bundled: boolean;
  homepage?: string;
  missing: SkillMissing;
};

export type SkillsSummary = {
  total: number;
  eligible: number;
  disabled: number;
  blocked: number;
  missingRequirements: number;
};

export type SkillsDashboardData = {
  workspaceDir: string;
  managedSkillsDir: string;
  summary: SkillsSummary;
  skills: SkillListEntry[];
};

export type SkillDetails = SkillListEntry & {
  filePath: string;
  baseDir: string;
  skillKey: string;
  always: boolean;
  requirements: SkillMissing;
  configChecks: Array<{
    path: string;
    satisfied: boolean;
  }>;
  install: SkillInstallHint[];
};

type SkillsListPayload = {
  workspaceDir: string;
  managedSkillsDir: string;
  skills: SkillListEntry[];
};

let dashboardCache:
  | {
      expiresAt: number;
      data: SkillsDashboardData;
    }
  | undefined;

const detailCache = new Map<
  string,
  {
    expiresAt: number;
    data: SkillDetails;
  }
>();

function normalizeMissing(input?: Partial<SkillMissing>): SkillMissing {
  return {
    bins: input?.bins ?? [],
    anyBins: input?.anyBins ?? [],
    env: input?.env ?? [],
    config: input?.config ?? [],
    os: input?.os ?? []
  };
}

function sortSkills(skills: SkillListEntry[]) {
  return [...skills].sort((left, right) => {
    const leftRank = left.eligible ? 1 : left.disabled || left.blockedByAllowlist ? 2 : 0;
    const rightRank = right.eligible ? 1 : right.disabled || right.blockedByAllowlist ? 2 : 0;

    if (leftRank !== rightRank) {
      return leftRank - rightRank;
    }

    return left.name.localeCompare(right.name, "zh-CN");
  });
}

function buildSummary(skills: SkillListEntry[]): SkillsSummary {
  return {
    total: skills.length,
    eligible: skills.filter((skill) => skill.eligible).length,
    disabled: skills.filter((skill) => skill.disabled).length,
    blocked: skills.filter((skill) => skill.blockedByAllowlist).length,
    missingRequirements: skills.filter((skill) => !skill.eligible).length
  };
}

async function runSkillsJsonCommand<T>(args: string[]): Promise<T> {
  const result = await tryRunOpenClawCli(args);

  if (!result.ok) {
    throw new Error(result.stderr || result.stdout || `openclaw ${args.join(" ")} failed`);
  }

  return parseOpenClawJsonOutput<T>(`${result.stdout}\n${result.stderr}`);
}

export async function loadSkillsDashboardData(): Promise<SkillsDashboardData> {
  if (dashboardCache && dashboardCache.expiresAt > Date.now()) {
    return dashboardCache.data;
  }

  const listPayload = await runSkillsJsonCommand<SkillsListPayload>(["skills", "list", "--json"]);
  const skills = sortSkills(
    listPayload.skills.map((skill) => ({
      ...skill,
      missing: normalizeMissing(skill.missing)
    }))
  );

  const data: SkillsDashboardData = {
    workspaceDir: listPayload.workspaceDir,
    managedSkillsDir: listPayload.managedSkillsDir,
    summary: buildSummary(skills),
    skills
  };

  dashboardCache = {
    data,
    expiresAt: Date.now() + SKILLS_TTL_MS
  };

  return data;
}

export async function loadSkillDetails(skillName: string): Promise<SkillDetails> {
  const cached = detailCache.get(skillName);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.data;
  }

  const data = await runSkillsJsonCommand<SkillDetails>([
    "skills",
    "info",
    skillName,
    "--json"
  ]);

  const normalized: SkillDetails = {
    ...data,
    missing: normalizeMissing(data.missing),
    requirements: normalizeMissing(data.requirements)
  };

  detailCache.set(skillName, {
    data: normalized,
    expiresAt: Date.now() + SKILLS_TTL_MS
  });

  return normalized;
}
