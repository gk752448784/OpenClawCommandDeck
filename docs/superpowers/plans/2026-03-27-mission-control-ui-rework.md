# Mission Control UI Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the frontend shell and key operational pages around a mission-control information hierarchy with clearer posture, triage, and action flow.

**Architecture:** Keep the existing Next.js route structure and loader boundaries, but refresh the global visual tokens, regroup navigation by operator workflow, and recompose the shared shell and high-traffic pages around a stronger first-screen hierarchy. Reuse current overview/control data models where practical, extending only the presentation contracts needed for the new shell and homepage.

**Tech Stack:** Next.js 15, React 19, TypeScript, plain global CSS, Vitest, ESLint

---

### Task 1: Reframe shared navigation and top-level shell

**Files:**
- Modify: `components/layout/side-nav.tsx`
- Modify: `components/layout/top-bar.tsx`
- Modify: `components/layout/app-shell.tsx`
- Modify: `app/globals.css`

- [ ] **Step 1: Write the failing shell expectations**

Review the existing shell-related rendering tests. If no shell-focused test exists, add a minimal render test covering grouped navigation labels and the compact header variant.

- [ ] **Step 2: Run targeted tests to verify the old shell contract fails**

Run: `npm run test -- tests/unit`
Expected: at least one shell-related assertion fails or no coverage exists and must be added before proceeding.

- [ ] **Step 3: Update sidebar structure**

Regroup links into `Observe`, `Act`, `Operate`, and `Configure`, keep route paths unchanged, and tighten brand/status copy.

- [ ] **Step 4: Update top-bar structure**

Make the hero variant posture-led for `workbench`, keep compact mode for secondary pages, and ensure shared status signals still read from the existing `TopBarModel`.

- [ ] **Step 5: Replace global shell styling**

Refresh tokens, spacing, planes, and layout classes in `app/globals.css` so the mission-control hierarchy propagates through the app.

- [ ] **Step 6: Re-run targeted tests**

Run: `npm run test -- tests/unit`
Expected: shell-related tests pass.

### Task 2: Recompose the workbench into a mission-control homepage

**Files:**
- Modify: `app/workbench/page.tsx`
- Modify: `components/overview/priority-cards.tsx`
- Modify: `components/shared/section-card.tsx`
- Modify: `components/shared/metric-card.tsx`
- Optional modify: `components/overview/right-rail.tsx`

- [ ] **Step 1: Add or update homepage-focused tests**

Cover the presence of posture hero, priority queue, system pulse, and quick actions in the rendered home view or supporting selector output.

- [ ] **Step 2: Run the targeted homepage tests and confirm they fail**

Run: `npm run test -- tests/unit`
Expected: assertions fail against the current homepage structure.

- [ ] **Step 3: Replace the current homepage composition**

Move from module-card-led layout to posture hero, triage block, system pulse, and quick action zones.

- [ ] **Step 4: Restyle shared overview surfaces**

Trim generic card framing so priority items feel dominant and support panels feel secondary.

- [ ] **Step 5: Verify responsive hierarchy**

Check the page at desktop and tablet widths and ensure the first-screen ordering still reads clearly.

- [ ] **Step 6: Re-run homepage tests**

Run: `npm run test -- tests/unit`
Expected: homepage-related assertions pass.

### Task 3: Bring alerts and control into the new system

**Files:**
- Modify: `app/alerts/page.tsx`
- Modify: `app/control/page.tsx`
- Modify: `components/alerts/alerts-overview.tsx`
- Modify: `components/control/recent-actions-panel.tsx`
- Optional modify: supporting control components if spacing/states need alignment

- [ ] **Step 1: Update page framing**

Use compact headers and reorganize sections so alerts feels triage-first and control feels action-zone-first.

- [ ] **Step 2: Reduce repeated panel chrome**

Align section spacing, titles, and supporting copy to the new shell instead of nested card stacks.

- [ ] **Step 3: Smoke-test page rendering**

Load these routes locally and confirm content still renders with the new shell classes and without layout regressions.

### Task 4: Final verification

**Files:**
- No code changes expected

- [ ] **Step 1: Run unit tests**

Run: `npm run test`
Expected: PASS

- [ ] **Step 2: Run typecheck**

Run: `npm run typecheck`
Expected: PASS

- [ ] **Step 3: Run lint**

Run: `npm run lint`
Expected: PASS

- [ ] **Step 4: Run a local visual smoke check**

Run the app locally and verify `/workbench`, `/alerts`, and `/control` at minimum.

- [ ] **Step 5: Summarize residual risks**

Document any routes still using the new shell without deeper page-specific redesign.
