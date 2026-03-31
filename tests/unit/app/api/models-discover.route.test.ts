import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

describe("POST /api/models/discover", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("normalizes an OpenAI-compatible models response", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          data: [
            {
              id: "gpt-5.4",
              name: "GPT-5.4",
              context_window: 256000,
              max_output_tokens: 64000,
              capabilities: {
                vision: true,
                reasoning: true
              }
            },
            {
              id: "gpt-5.3-codex"
            }
          ]
        })
      })
    );

    const { POST } = await import("@/app/api/models/discover/route");
    const request = new NextRequest("http://localhost/api/models/discover", {
      method: "POST",
      body: JSON.stringify({
        providerKey: "openai",
        baseUrl: "https://api.openai.com/v1",
        apiType: "openai-completions",
        apiKey: "secret"
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.ok).toBe(true);
    expect(payload.models).toEqual([
      expect.objectContaining({
        provider: "openai",
        id: "gpt-5.4",
        name: "GPT-5.4",
        input: ["text", "image"],
        contextWindow: 256000,
        maxTokens: 64000,
        thinking: true
      }),
      expect.objectContaining({
        provider: "openai",
        id: "gpt-5.3-codex",
        name: "gpt-5.3-codex",
        input: ["text"],
        thinking: false
      })
    ]);
  });

  it("rejects unsupported api types", async () => {
    const { POST } = await import("@/app/api/models/discover/route");
    const request = new NextRequest("http://localhost/api/models/discover", {
      method: "POST",
      body: JSON.stringify({
        providerKey: "openai",
        baseUrl: "https://api.openai.com/v1",
        apiType: "custom",
        apiKey: "secret"
      }),
      headers: {
        "Content-Type": "application/json"
      }
    });

    const response = await POST(request);
    const payload = await response.json();

    expect(response.status).toBe(400);
    expect(payload.error).toContain("openai-completions");
  });
});
