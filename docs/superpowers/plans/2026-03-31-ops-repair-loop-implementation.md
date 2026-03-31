# Ops Repair Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first phase of a root-cause-driven repair loop for OpenClaw Command Deck, covering channel/plugin issues, model/gateway issues, and log visibility for agent/session troubleshooting.

**Architecture:** Introduce a new server-side issue pipeline with four layers: signal collection, root-cause classification, repair-plan generation, and post-repair verification. Keep the existing pages, but upgrade alerts into a unified issues surface and thread repair actions plus verification results back into the UI. Reuse current CLI execution and dashboard-loading patterns instead of adding a generic automation engine.

**Tech Stack:** Next.js App Router, React 19, TypeScript, Vitest, existing OpenClaw CLI adapters and selectors

---

## File Map

### Existing files to modify

- Modify: `lib/types/view-models.ts`
  Responsibility: add issue, repair-plan, verification, and log-entry view models.
- Modify: `lib/server/load-dashboard-data.ts`
  Responsibility: load issue data alongside existing dashboard data, including agent/session log signals.
- Modify: `lib/server/openclaw-cli.ts`
  Responsibility: reuse CLI execution helpers for verification paths if needed.
- Modify: `lib/control/commands.ts`
  Responsibility: expose any missing low-risk and confirm-required repair commands used by repair plans.
- Modify: `app/api/alerts/route.ts`
  Responsibility: replace alert payloads with unified issue payloads or redirect to new issue loader.
- Modify: `app/api/diagnostics/route.ts`
  Responsibility: expose richer diagnostic evidence if verification depends on it.
- Modify: `app/alerts/page.tsx`
  Responsibility: switch from alert list page to problem/issue triage page.
- Modify: `components/alerts/alerts-overview.tsx`
  Responsibility: render issue cards, root causes, repair actions, and verification states.
- Modify: `app/sessions/page.tsx`
  Responsibility: expose new log visibility entry points for troubleshooting.
- Modify: `components/tables/agents-table.tsx`
  Responsibility: surface agent issue/log indicators if this is the chosen location for agent troubleshooting links.
- Modify: `components/diagnostics/diagnostics-panel.tsx`
  Responsibility: show issue evidence and verification evidence, not only runtime summary.
- Modify: `tests/unit/app/alerts/page.test.tsx`
  Responsibility: cover the upgraded issue triage page.
- Modify: `tests/unit/components/alerts/alerts-overview.test.tsx`
  Responsibility: cover root-cause and verification rendering.
- Modify: `tests/unit/lib/selectors/alerts.test.ts`
  Responsibility: migrate alert-only expectations to issue model expectations where appropriate.
- Modify: `tests/unit/lib/selectors/diagnostics.test.ts`
  Responsibility: cover richer diagnostics and evidence structures if changed.

### New files to create

- Create: `lib/types/issues.ts`
  Responsibility: canonical issue-domain types shared by signals, classifiers, repair plans, and verification.
- Create: `lib/signals/channels.ts`
  Responsibility: collect raw channel/plugin state signals from config.
- Create: `lib/signals/models.ts`
  Responsibility: collect primary-model and candidate-model signals from config.
- Create: `lib/signals/gateway.ts`
  Responsibility: collect gateway reachability and related diagnostics signals.
- Create: `lib/signals/logs.ts`
  Responsibility: normalize recent log sources for agent/session troubleshooting.
- Create: `lib/root-causes/channels.ts`
  Responsibility: classify channel/plugin root causes.
- Create: `lib/root-causes/models.ts`
  Responsibility: classify model/gateway root causes.
- Create: `lib/root-causes/logs.ts`
  Responsibility: classify log-based agent/session failure root causes.
- Create: `lib/repair/plans.ts`
  Responsibility: map root causes to repair plans, risk tiers, and fallback manual steps.
- Create: `lib/repair/verify.ts`
  Responsibility: run post-repair verification checks and normalize outcomes.
- Create: `lib/issues/build-issues.ts`
  Responsibility: orchestrate signals -> root causes -> repair plans -> issue view model.
- Create: `app/api/issues/route.ts`
  Responsibility: return unified issue list payload.
- Create: `app/api/issues/[issueId]/repair/route.ts`
  Responsibility: execute a repair action for a given issue.
- Create: `app/api/issues/[issueId]/verify/route.ts`
  Responsibility: rerun verification for a given issue.
- Create: `components/issues/issue-card.tsx`
  Responsibility: reusable issue card UI with evidence, actions, and verification summary.
- Create: `components/issues/verification-badge.tsx`
  Responsibility: consistent verification-status UI.
- Create: `components/sessions/session-log-panel.tsx`
  Responsibility: render recent log excerpts and troubleshooting entry points on session/agent surfaces.
- Create: `tests/unit/lib/issues/build-issues.test.ts`
  Responsibility: end-to-end issue-model construction tests using fixtures.
- Create: `tests/unit/lib/root-causes/channels.test.ts`
  Responsibility: classifier tests for channel/plugin root causes.
- Create: `tests/unit/lib/root-causes/models.test.ts`
  Responsibility: classifier tests for model/gateway root causes.
- Create: `tests/unit/lib/root-causes/logs.test.ts`
  Responsibility: classifier tests for log-derived troubleshooting issues.
- Create: `tests/unit/lib/repair/plans.test.ts`
  Responsibility: repair-plan generation tests.
- Create: `tests/unit/lib/repair/verify.test.ts`
  Responsibility: post-repair verification tests.
- Create: `tests/unit/app/api/issues.route.test.ts`
  Responsibility: unified issue API tests.
- Create: `tests/unit/app/api/issues-repair.route.test.ts`
  Responsibility: repair execution API tests.
- Create: `tests/unit/app/api/issues-verify.route.test.ts`
  Responsibility: verification API tests.

## Task 1: Define the issue domain model

**Files:**
- Create: `lib/types/issues.ts`
- Modify: `lib/types/view-models.ts`
- Test: `tests/unit/lib/issues/build-issues.test.ts`

- [ ] **Step 1: Write the failing domain-shape test**

```ts
import { describe, expect, it } from "vitest";

import type { Repairability, VerificationStatus } from "@/lib/types/issues";

describe("issue domain types", () => {
  it("supports repairability and verification states needed by the first-phase repair loop", () => {
    const repairability: Repairability = "auto";
    const verification: VerificationStatus = "resolved";

    expect(repairability).toBe("auto");
    expect(verification).toBe("resolved");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm run test -- tests/unit/lib/issues/build-issues.test.ts`
Expected: FAIL because `lib/types/issues.ts` or its exported types do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Add canonical first-phase issue types in `lib/types/issues.ts`, including:

- `IssueSource`
- `RootCauseType`
- `Repairability`
- `VerificationStatus`
- `IssueEvidence`
- `RepairAction`
- `RepairPlan`
- `Issue`

Update `lib/types/view-models.ts` only where page-facing types should reference the new issue domain.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm run test -- tests/unit/lib/issues/build-issues.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/types/issues.ts lib/types/view-models.ts tests/unit/lib/issues/build-issues.test.ts
git commit -m "feat: add issue domain model"
```

## Task 2: Add signal collectors for config, gateway, and logs

**Files:**
- Create: `lib/signals/channels.ts`
- Create: `lib/signals/models.ts`
- Create: `lib/signals/gateway.ts`
- Create: `lib/signals/logs.ts`
- Modify: `lib/server/load-dashboard-data.ts`
- Test: `tests/unit/lib/root-causes/channels.test.ts`
- Test: `tests/unit/lib/root-causes/models.test.ts`
- Test: `tests/unit/lib/root-causes/logs.test.ts`

- [ ] **Step 1: Write failing tests for raw signal extraction**

Add tests that prove the signal collectors can extract:

- channel enabled state
- plugin enabled/install state
- primary model key and candidate models
- gateway reachability
- recent log excerpts or patterns for agent/session troubleshooting

- [ ] **Step 2: Run targeted tests to verify they fail**

Run:

```bash
npm run test -- tests/unit/lib/root-causes/channels.test.ts
npm run test -- tests/unit/lib/root-causes/models.test.ts
npm run test -- tests/unit/lib/root-causes/logs.test.ts
```

Expected: FAIL because the signal collector modules do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Implement focused collectors that return normalized raw signals rather than view models. Reuse existing config, diagnostics, and session data loading patterns. Do not embed root-cause rules here.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run the three targeted tests again.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/signals lib/server/load-dashboard-data.ts tests/unit/lib/root-causes/channels.test.ts tests/unit/lib/root-causes/models.test.ts tests/unit/lib/root-causes/logs.test.ts
git commit -m "feat: add issue signal collectors"
```

## Task 3: Implement root-cause classifiers

**Files:**
- Create: `lib/root-causes/channels.ts`
- Create: `lib/root-causes/models.ts`
- Create: `lib/root-causes/logs.ts`
- Test: `tests/unit/lib/root-causes/channels.test.ts`
- Test: `tests/unit/lib/root-causes/models.test.ts`
- Test: `tests/unit/lib/root-causes/logs.test.ts`

- [ ] **Step 1: Write failing tests for root-cause outputs**

Each classifier test should prove that the right root cause is emitted for representative fixture inputs, including:

- `plugin_disabled`
- `channel_plugin_mismatch`
- `primary_model_missing`
- `gateway_unreachable`
- `session_log_error_detected`

- [ ] **Step 2: Run targeted tests to verify they fail for the expected reason**

Run:

```bash
npm run test -- tests/unit/lib/root-causes/channels.test.ts tests/unit/lib/root-causes/models.test.ts tests/unit/lib/root-causes/logs.test.ts
```

Expected: FAIL because classifier behavior is missing or incomplete.

- [ ] **Step 3: Write minimal implementation**

Implement small classifier functions that accept normalized signals and return typed root-cause results with:

- `type`
- `severity`
- `summary`
- `details`
- `impactScope`
- `evidence`

Keep rule ordering explicit and deterministic.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run the same targeted tests.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/root-causes tests/unit/lib/root-causes/channels.test.ts tests/unit/lib/root-causes/models.test.ts tests/unit/lib/root-causes/logs.test.ts
git commit -m "feat: classify root causes for issues"
```

## Task 4: Build repair plans and verification logic

**Files:**
- Create: `lib/repair/plans.ts`
- Create: `lib/repair/verify.ts`
- Modify: `lib/control/commands.ts`
- Test: `tests/unit/lib/repair/plans.test.ts`
- Test: `tests/unit/lib/repair/verify.test.ts`

- [ ] **Step 1: Write failing tests for repairability and verification**

Add tests that prove:

- low-risk fixes are marked `auto`
- model switch or gateway restart are marked `confirm`
- unsupported cases are marked `manual`
- verification returns `resolved`, `partially_resolved`, or `unresolved` based on fresh signals

- [ ] **Step 2: Run targeted tests to verify they fail**

Run:

```bash
npm run test -- tests/unit/lib/repair/plans.test.ts tests/unit/lib/repair/verify.test.ts
```

Expected: FAIL because repair plan and verification modules do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Implement:

- a repair-plan registry keyed by root-cause type
- action definitions referencing controlled CLI actions only
- a verifier that reruns the relevant checks rather than trusting action success

Add any missing command builders in `lib/control/commands.ts`.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run the same two test files.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repair lib/control/commands.ts tests/unit/lib/repair/plans.test.ts tests/unit/lib/repair/verify.test.ts
git commit -m "feat: add repair plans and verification"
```

## Task 5: Build the unified issue pipeline and issue API

**Files:**
- Create: `lib/issues/build-issues.ts`
- Create: `app/api/issues/route.ts`
- Create: `app/api/issues/[issueId]/repair/route.ts`
- Create: `app/api/issues/[issueId]/verify/route.ts`
- Modify: `app/api/alerts/route.ts`
- Test: `tests/unit/lib/issues/build-issues.test.ts`
- Test: `tests/unit/app/api/issues.route.test.ts`
- Test: `tests/unit/app/api/issues-repair.route.test.ts`
- Test: `tests/unit/app/api/issues-verify.route.test.ts`

- [ ] **Step 1: Write failing tests for unified issue building and API responses**

Cover:

- merged issue list from multiple sources
- stable issue IDs
- repair endpoint action gating
- verify endpoint response shape
- legacy alerts endpoint compatibility or redirect behavior

- [ ] **Step 2: Run targeted tests to verify they fail**

Run:

```bash
npm run test -- tests/unit/lib/issues/build-issues.test.ts tests/unit/app/api/issues.route.test.ts tests/unit/app/api/issues-repair.route.test.ts tests/unit/app/api/issues-verify.route.test.ts
```

Expected: FAIL because the orchestration and routes do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Implement one orchestration function that:

1. loads the needed source data
2. collects signals
3. classifies root causes
4. attaches repair plans
5. attaches latest verification state

Add routes that expose and exercise that pipeline without duplicating orchestration logic.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run the same four test files.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/issues app/api/issues app/api/alerts/route.ts tests/unit/lib/issues/build-issues.test.ts tests/unit/app/api/issues.route.test.ts tests/unit/app/api/issues-repair.route.test.ts tests/unit/app/api/issues-verify.route.test.ts
git commit -m "feat: add unified issues api"
```

## Task 6: Upgrade the alert page into an issue triage surface

**Files:**
- Create: `components/issues/issue-card.tsx`
- Create: `components/issues/verification-badge.tsx`
- Modify: `app/alerts/page.tsx`
- Modify: `components/alerts/alerts-overview.tsx`
- Modify: `lib/types/view-models.ts`
- Test: `tests/unit/app/alerts/page.test.tsx`
- Test: `tests/unit/components/alerts/alerts-overview.test.tsx`

- [ ] **Step 1: Write failing UI tests**

Cover:

- root-cause label rendering
- repairability rendering
- verification badge rendering
- issue evidence expansion or inline detail rendering
- compatibility for existing cron repair embed where still applicable

- [ ] **Step 2: Run targeted tests to verify they fail**

Run:

```bash
npm run test -- tests/unit/app/alerts/page.test.tsx tests/unit/components/alerts/alerts-overview.test.tsx
```

Expected: FAIL because the UI still assumes the old alert-only shape.

- [ ] **Step 3: Write minimal implementation**

Refactor the page to consume issue data and add reusable issue UI primitives. Keep visual changes incremental; focus on information density, evidence clarity, and repair flow clarity.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run the same two tests.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/alerts/page.tsx components/alerts/alerts-overview.tsx components/issues lib/types/view-models.ts tests/unit/app/alerts/page.test.tsx tests/unit/components/alerts/alerts-overview.test.tsx
git commit -m "feat: upgrade alerts page to issue triage"
```

## Task 7: Add agent/session log visibility

**Files:**
- Create: `components/sessions/session-log-panel.tsx`
- Modify: `app/sessions/page.tsx`
- Modify: `components/tables/agents-table.tsx`
- Modify: `components/diagnostics/diagnostics-panel.tsx`
- Test: `tests/unit/app/workbench/page.test.tsx`
- Test: `tests/unit/lib/selectors/sessions.test.ts`
- Test: `tests/unit/lib/selectors/diagnostics.test.ts`

- [ ] **Step 1: Write failing tests for log visibility entry points**

Cover:

- recent log excerpt rendering
- error-pattern surfacing for troubleshooting
- navigation or inline links from sessions/agents to logs
- diagnostics page showing issue evidence, not just raw summaries

- [ ] **Step 2: Run targeted tests to verify they fail**

Run:

```bash
npm run test -- tests/unit/lib/selectors/sessions.test.ts tests/unit/lib/selectors/diagnostics.test.ts tests/unit/app/workbench/page.test.tsx
```

Expected: FAIL because no dedicated log-visibility UI exists yet.

- [ ] **Step 3: Write minimal implementation**

Add a compact log panel and wire it into session/agent-oriented surfaces. Reuse normalized log signals; avoid building a full log viewer in phase one.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run the same tests.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add components/sessions/session-log-panel.tsx app/sessions/page.tsx components/tables/agents-table.tsx components/diagnostics/diagnostics-panel.tsx tests/unit/lib/selectors/sessions.test.ts tests/unit/lib/selectors/diagnostics.test.ts tests/unit/app/workbench/page.test.tsx
git commit -m "feat: add troubleshooting log visibility"
```

## Task 8: Full verification and cleanup

**Files:**
- Modify: any touched files from prior tasks if verification exposes gaps
- Test: full repository checks

- [ ] **Step 1: Run focused tests for touched modules**

Run all targeted issue, repair, UI, and diagnostics tests added in earlier tasks.
Expected: PASS

- [ ] **Step 2: Run repository verification**

Run:

```bash
npm run typecheck
npm run lint
npm run test
npm run build
```

Expected:

- `typecheck`: PASS
- `lint`: PASS
- `test`: PASS
- `build`: PASS

- [ ] **Step 3: Fix any failures minimally**

If verification reveals regressions, patch only the affected files and rerun the failing command before moving on.

- [ ] **Step 4: Commit final stabilization**

```bash
git add .
git commit -m "chore: stabilize issue repair loop phase one"
```
