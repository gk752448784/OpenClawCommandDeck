import { describe, expect, it } from "vitest";

import {
  extractJsonPayload,
  parseOpenClawJsonOutput,
  summarizeLogLines
} from "@/lib/server/openclaw-cli";

describe("openclaw cli helpers", () => {
  it("extracts a json payload after plugin noise", () => {
    const raw = `[plugins] registered\n[plugins] again\n{"ok":true,"count":2}`;

    expect(extractJsonPayload(raw)).toBe('{"ok":true,"count":2}');
  });

  it("parses status output with plugin noise", () => {
    const raw = `[plugins] registered\n{"runtimeVersion":"2026.3.13","gateway":{"reachable":false}}`;

    expect(
      parseOpenClawJsonOutput<{ runtimeVersion: string; gateway: { reachable: boolean } }>(raw)
    ).toEqual({
      runtimeVersion: "2026.3.13",
      gateway: {
        reachable: false
      }
    });
  });

  it("keeps only actual log lines in the log summary", () => {
    const raw = `[plugins] bootstrap\nLog file: /tmp/openclaw.log\n2026-03-26T03:13:03.415Z info gateway/ws missing scope\n2026-03-26T03:13:03.419Z info gateway/ws config.get failed`;

    expect(summarizeLogLines(raw)).toEqual([
      "2026-03-26T03:13:03.415Z info gateway/ws missing scope",
      "2026-03-26T03:13:03.419Z info gateway/ws config.get failed"
    ]);
  });
});
