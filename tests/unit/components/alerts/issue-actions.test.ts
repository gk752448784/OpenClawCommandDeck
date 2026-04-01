import { describe, expect, it } from "vitest";

import { buildIssueActionPath } from "@/components/alerts/issue-actions";

describe("issue action paths", () => {
  it("encodes issue ids before building repair and verify urls", () => {
    expect(buildIssueActionPath("config:primary_model_missing:bltcy/gpt-5.4", "verify")).toBe(
      "/api/issues/config%3Aprimary_model_missing%3Abltcy%2Fgpt-5.4/verify"
    );
    expect(buildIssueActionPath("config:primary_model_missing:bltcy/gpt-5.4", "repair")).toBe(
      "/api/issues/config%3Aprimary_model_missing%3Abltcy%2Fgpt-5.4/repair"
    );
  });
});
