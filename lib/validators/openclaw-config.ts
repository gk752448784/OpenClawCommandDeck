import { z } from "zod";

const modelSchema = z.object({
  id: z.string(),
  name: z.string().optional(),
  api: z.string().optional(),
  reasoning: z.boolean().optional(),
  input: z.array(z.string()).optional(),
  contextWindow: z.number().optional(),
  maxTokens: z.number().optional(),
  cost: z
    .object({
      input: z.number().optional(),
      output: z.number().optional(),
      cacheRead: z.number().optional(),
      cacheWrite: z.number().optional()
    })
    .optional()
});

const providerSchema = z.object({
  baseUrl: z.string().optional(),
  apiKey: z.string().optional(),
  api: z.string().optional(),
  models: z.array(modelSchema).optional()
});

const pluginEntrySchema = z.object({
  enabled: z.boolean().optional()
}).passthrough();

const pluginInstallSchema = z.object({
  source: z.string().optional(),
  spec: z.string().optional(),
  installPath: z.string().optional(),
  version: z.string().optional(),
  resolvedName: z.string().optional(),
  resolvedVersion: z.string().optional(),
  resolvedSpec: z.string().optional(),
  resolvedAt: z.string().optional(),
  installedAt: z.string().optional()
}).passthrough();

const configSchema = z.object({
  meta: z
    .object({
      lastTouchedVersion: z.string().optional(),
      lastTouchedAt: z.string().optional()
    })
    .optional(),
  wizard: z
    .object({
      lastRunAt: z.string().optional(),
      lastRunVersion: z.string().optional(),
      lastRunCommand: z.string().optional(),
      lastRunMode: z.string().optional()
    })
    .optional(),
  auth: z
    .object({
      profiles: z
        .record(
          z.object({
            provider: z.string().optional(),
            mode: z.string().optional()
          })
        )
        .optional()
    })
    .optional(),
  models: z.object({
    providers: z.record(providerSchema)
  }),
  agents: z.object({
    defaults: z.object({
      models: z.record(z.unknown()).default({}),
      model: z.object({
        primary: z.string()
      }),
      workspace: z.string()
    }),
    list: z.array(
      z.object({
        id: z.string(),
        name: z.string().optional(),
        workspace: z.string(),
        agentDir: z.string()
      })
    )
  }),
  channels: z.object({
    feishu: z
      .object({
        enabled: z.boolean().optional(),
        appSecret: z.string().optional(),
        connectionMode: z.string().optional(),
        domain: z.string().optional(),
        groupPolicy: z.string().optional(),
        streaming: z.union([z.boolean(), z.string()]).optional()
      })
      .passthrough()
      .optional(),
    discord: z
      .object({
        enabled: z.boolean().optional(),
        groupPolicy: z.string().optional(),
        streaming: z.union([z.boolean(), z.string()]).optional()
      })
      .passthrough()
      .optional()
  }).passthrough(),
  gateway: z.object({
    port: z.number(),
    mode: z.string(),
    bind: z.string(),
    auth: z.object({
      mode: z.string(),
      token: z.string().optional()
    })
  }),
  plugins: z
    .object({
      allow: z.array(z.string()).optional(),
      entries: z.record(pluginEntrySchema).optional(),
      installs: z.record(pluginInstallSchema).optional()
    })
    .passthrough()
});

export type OpenClawConfig = z.infer<typeof configSchema>;

export function parseOpenClawConfig(data: unknown) {
  return configSchema.safeParse(data);
}
