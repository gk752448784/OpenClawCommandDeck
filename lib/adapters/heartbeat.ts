import type { LoadResult } from "@/lib/types/raw";
import { safeReadTextFile } from "@/lib/server/safe-read";

export async function loadHeartbeatGuide(path: string): Promise<LoadResult<string>> {
  return safeReadTextFile(path);
}
