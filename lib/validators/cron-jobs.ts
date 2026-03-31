import { z } from "zod";

const cronJobSchema = z.object({
  id: z.string(),
  agentId: z.string(),
  name: z.string(),
  description: z.string().optional(),
  enabled: z.boolean(),
  schedule: z.object({
    kind: z.string(),
    expr: z.string(),
    tz: z.string()
  }),
  delivery: z
    .object({
      mode: z.string(),
      channel: z.string().optional()
    })
    .passthrough(),
  state: z.object({
    nextRunAtMs: z.number().optional(),
    lastRunAtMs: z.number().optional(),
    lastRunStatus: z.string().optional(),
    lastStatus: z.string().optional(),
    lastDurationMs: z.number().optional(),
    lastError: z.string().optional(),
    consecutiveErrors: z.number().optional()
  })
});

const cronJobsSchema = z.object({
  version: z.number(),
  jobs: z.array(cronJobSchema)
});

export type CronJobs = z.infer<typeof cronJobsSchema>;
export type CronJob = z.infer<typeof cronJobSchema>;

export function parseCronJobs(data: unknown) {
  return cronJobsSchema.safeParse(data);
}
