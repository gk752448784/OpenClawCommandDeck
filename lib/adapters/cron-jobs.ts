import type { LoadResult } from "@/lib/types/raw";
import type { CronJobs } from "@/lib/validators/cron-jobs";
import { parseCronJobs } from "@/lib/validators/cron-jobs";
import { safeReadJsonFile } from "@/lib/server/safe-read";

export async function loadCronJobs(path: string): Promise<LoadResult<CronJobs>> {
  const result = await safeReadJsonFile(path);
  if (!result.ok) {
    return result;
  }

  const parsed = parseCronJobs(result.data);
  if (!parsed.success) {
    return {
      ok: false,
      error: {
        code: "invalid_shape",
        message: parsed.error.issues[0]?.message ?? "Invalid cron jobs file"
      }
    };
  }

  return {
    ok: true,
    data: parsed.data
  };
}
