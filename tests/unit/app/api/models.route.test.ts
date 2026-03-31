import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const safeReadJsonFile = vi.fn();
const writeFile = vi.fn();

const { executeCliCommand } = vi.hoisted(() => ({
  executeCliCommand: vi.fn()
}));

vi.mock("@/lib/server/safe-read", () => ({
  safeReadJsonFile
}));

vi.mock("node:fs/promises", () => ({
  writeFile
}));

vi.mock("@/lib/control/execute", () => ({
  executeCliCommand: (...args: unknown[]) => executeCliCommand(...args)
}));

describe("POST /api/models", () => {
  const baseConfig = {
    models: {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          apiKey: "secret",
          api: "openai-completions",
          models: [
            {
              id: "gpt-5.3-codex",
              name: "GPT-5.3 Codex",
              input: ["text"],
              contextWindow: 200000,
              maxTokens: 32000,
              reasoning: true
            }
          ]
        }
      }
    },
    agents: {
      defaults: {
        model: {
          primary: "openai/gpt-5.3-codex"
        },
        models: {
          "openai/gpt-5.3-codex": {
            alias: "Codex"
          }
        }
      }
    }
  };

  beforeEach(() => {
    vi.clearAllMocks();
    vi.unstubAllEnvs();
    safeReadJsonFile.mockResolvedValue({
      ok: true,
      data: structuredClone(baseConfig)
    });
    writeFile.mockResolvedValue(undefined);
    executeCliCommand.mockResolvedValue({
      ok: true,
      stdout: "",
      stderr: ""
    });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("persists provider and model additions alongside defaults", async () => {
    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [
          {
            key: "openai/gpt-5.3-codex",
            alias: "OpenAI Gateway 5.3",
            allowed: true
          },
          {
            key: "bailian/qwen3.5-plus",
            alias: "百炼增强",
            allowed: true
          }
        ],
        providerAdditions: [
          {
            key: "bailian",
            baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            api: "openai-completions",
            apiKey: "dashscope-key"
          }
        ],
        modelAdditions: [
          {
            provider: "bailian",
            id: "qwen3.5-plus",
            name: "Qwen 3.5 Plus",
            input: ["text"],
            contextWindow: 131072,
            maxTokens: 16384,
            reasoning: true
          }
        ]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.restartOk).toBe(true);
    expect(writeFile).toHaveBeenCalledTimes(1);
    expect(executeCliCommand).toHaveBeenCalledTimes(1);
    expect(executeCliCommand).toHaveBeenCalledWith({
      command: "openclaw",
      args: ["gateway", "restart"]
    });

    const [, saved] = writeFile.mock.calls[0];
    const persisted = JSON.parse(saved as string);

    expect(persisted.models.providers.openai.apiKey).toBe("secret");
    expect(persisted.models.providers.bailian.baseUrl).toBe(
      "https://dashscope.aliyuncs.com/compatible-mode/v1"
    );
    expect(persisted.models.providers.bailian.apiKey).toBe("dashscope-key");
    expect(persisted.models.providers.bailian.models).toEqual([
      expect.objectContaining({
        id: "qwen3.5-plus",
        name: "Qwen 3.5 Plus",
        input: ["text"],
        contextWindow: 131072,
        maxTokens: 16384,
        reasoning: true
      })
    ]);
    expect(persisted.agents.defaults.models["bailian/qwen3.5-plus"]).toEqual({
      alias: "百炼增强"
    });
  });

  it("merges discovered models by overriding the same key and appending new keys", async () => {
    safeReadJsonFile.mockResolvedValue({
      ok: true,
      data: {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: "secret",
              api: "openai-completions",
              models: [
                {
                  id: "gpt-5.3-codex",
                  name: "Old Name",
                  input: ["text"],
                  contextWindow: 200000,
                  maxTokens: 32000,
                  reasoning: false
                }
              ]
            }
          }
        },
        agents: {
          defaults: {
            model: {
              primary: "openai/gpt-5.3-codex"
            },
            models: {
              "openai/gpt-5.3-codex": {
                alias: "Custom Alias"
              }
            }
          }
        }
      }
    });

    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [
          {
            key: "openai/gpt-5.3-codex",
            alias: "Custom Alias",
            allowed: true
          }
        ],
        discoveredModels: [
          {
            provider: "openai",
            id: "gpt-5.3-codex",
            name: "GPT-5.3 Codex",
            input: ["text", "image"],
            contextWindow: 256000,
            maxTokens: 64000,
            thinking: true
          },
          {
            provider: "openai",
            id: "gpt-5.4",
            name: "GPT-5.4",
            input: ["text"],
            contextWindow: 256000,
            maxTokens: 64000,
            thinking: true
          }
        ]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);

    const [, saved] = writeFile.mock.calls[0];
    const persisted = JSON.parse(saved as string);

    expect(persisted.models.providers.openai.models).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: "gpt-5.3-codex",
          name: "GPT-5.3 Codex",
          input: ["text", "image"],
          contextWindow: 256000,
          maxTokens: 64000,
          reasoning: true
        }),
        expect.objectContaining({
          id: "gpt-5.4",
          name: "GPT-5.4"
        })
      ])
    );
    expect(persisted.agents.defaults.models["openai/gpt-5.3-codex"]).toEqual({
      alias: "Custom Alias"
    });
  });

  it("rejects model additions for unknown providers", async () => {
    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [
          {
            key: "openai/gpt-5.3-codex",
            alias: "Codex",
            allowed: true
          }
        ],
        modelAdditions: [
          {
            provider: "missing",
            id: "new-model",
            name: "New Model",
            input: ["text"],
            contextWindow: 64000,
            maxTokens: 8192,
            reasoning: false
          }
        ]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(400);
    expect(payload.error).toContain("provider");
    expect(writeFile).not.toHaveBeenCalled();
    expect(executeCliCommand).not.toHaveBeenCalled();
  });

  it("removes models and providers when the payload requests deletion", async () => {
    safeReadJsonFile.mockResolvedValue({
      ok: true,
      data: {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: "secret",
              api: "openai-completions",
              models: [
                {
                  id: "gpt-5.3-codex",
                  name: "GPT-5.3 Codex",
                  input: ["text"]
                }
              ]
            },
            bailian: {
              baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              api: "openai-completions",
              models: [
                {
                  id: "qwen3.5-plus",
                  name: "Qwen 3.5 Plus",
                  input: ["text"]
                }
              ]
            }
          }
        },
        agents: {
          defaults: {
            model: {
              primary: "openai/gpt-5.3-codex"
            },
            models: {
              "openai/gpt-5.3-codex": {
                alias: "Codex"
              },
              "bailian/qwen3.5-plus": {
                alias: "百炼增强"
              }
            }
          }
        }
      }
    });

    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [
          {
            key: "openai/gpt-5.3-codex",
            alias: "Codex",
            allowed: true
          }
        ],
        modelRemovals: ["bailian/qwen3.5-plus"],
        providerRemovals: ["bailian"]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.restartOk).toBe(true);
    expect(executeCliCommand).toHaveBeenCalledTimes(1);

    const [, saved] = writeFile.mock.calls[0];
    const persisted = JSON.parse(saved as string);

    expect(persisted.models.providers.bailian).toBeUndefined();
    expect(persisted.agents.defaults.models["bailian/qwen3.5-plus"]).toBeUndefined();
  });

  it("rejects deleting the current default model", async () => {
    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [],
        modelRemovals: ["openai/gpt-5.3-codex"]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(400);
    expect(payload.error).toContain("默认主模型");
    expect(writeFile).not.toHaveBeenCalled();
    expect(executeCliCommand).not.toHaveBeenCalled();
  });

  it("deletes a provider together with its non-primary models", async () => {
    safeReadJsonFile.mockResolvedValue({
      ok: true,
      data: {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: "secret",
              api: "openai-completions",
              models: [
                {
                  id: "gpt-5.3-codex",
                  name: "GPT-5.3 Codex",
                  input: ["text"]
                }
              ]
            },
            bailian: {
              baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              api: "openai-completions",
              models: [
                {
                  id: "qwen3.5-plus",
                  name: "Qwen 3.5 Plus",
                  input: ["text"]
                },
                {
                  id: "qwen-max",
                  name: "Qwen Max",
                  input: ["text"]
                }
              ]
            }
          }
        },
        agents: {
          defaults: {
            model: {
              primary: "openai/gpt-5.3-codex"
            },
            models: {
              "openai/gpt-5.3-codex": {
                alias: "Codex"
              }
            }
          }
        }
      }
    });

    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [
          {
            key: "openai/gpt-5.3-codex",
            alias: "Codex",
            allowed: true
          }
        ],
        providerRemovals: ["bailian"],
        modelRemovals: ["bailian/qwen3.5-plus", "bailian/qwen-max"]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.restartOk).toBe(true);
  });

  it("skips gateway restart when OPENCLAW_SKIP_GATEWAY_RESTART_ON_MODEL_CHANGE is set", async () => {
    vi.stubEnv("OPENCLAW_SKIP_GATEWAY_RESTART_ON_MODEL_CHANGE", "1");
    const { POST } = await import("@/app/api/models/route");
    const request = new NextRequest("http://localhost/api/models", {
      method: "POST",
      body: JSON.stringify({
        primaryModel: "openai/gpt-5.3-codex",
        models: [
          {
            key: "openai/gpt-5.3-codex",
            alias: "Codex",
            allowed: true
          }
        ]
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.restartSkipped).toBe(true);
    expect(executeCliCommand).not.toHaveBeenCalled();
  });
});
