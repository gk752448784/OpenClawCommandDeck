import os from "node:os";
import path from "node:path";

export const OPENCLAW_ROOT =
  process.env.OPENCLAW_ROOT ?? path.join(os.homedir(), ".openclaw");

export const APP_NAME =
  process.env.NEXT_PUBLIC_APP_NAME ?? "OpenClaw 指挥舱";
