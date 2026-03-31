# Command Center Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the shell and homepage into a Chinese operations control center with stronger health summary, grouped navigation, and a clearer homepage hierarchy.

**Architecture:** Keep the existing routes and data-loading flow, but reshape the overview view-model and replace the homepage composition around a new command-center hero, status metrics, focus panels, and grouped entry cards. Refresh the shell with a richer sidebar, top header, and global design tokens so other pages inherit the new product language without being rewritten.

**Tech Stack:** Next.js 15, React 19, TypeScript, plain global CSS, Vitest

---

### Task 1: Lock the new overview contract in tests

**Files:**
- Modify: `tests/unit/lib/selectors/overview.test.ts`
- Modify: `lib/types/view-models.ts`
- Modify: `lib/selectors/overview.ts`

- [ ] Step 1: Add expectations for the renamed product framing, grouped quick actions, and new homepage sections.
- [ ] Step 2: Run `npm run test -- tests/unit/lib/selectors/overview.test.ts` and confirm the test fails for the new contract.
- [ ] Step 3: Update the overview model types and selector output with only the fields needed by the new shell and homepage.
- [ ] Step 4: Re-run `npm run test -- tests/unit/lib/selectors/overview.test.ts` and confirm it passes.

### Task 2: Rebuild the application shell

**Files:**
- Modify: `components/layout/side-nav.tsx`
- Modify: `components/layout/top-bar.tsx`
- Modify: `components/layout/app-shell.tsx`
- Modify: `app/globals.css`

- [ ] Step 1: Keep shell component boundaries intact and update markup for grouped navigation, product metadata, and stronger top header actions.
- [ ] Step 2: Replace the global visual tokens and shell layout styles to match the new control-center language.
- [ ] Step 3: Run targeted tests/typecheck to catch contract drift from the shell changes.

### Task 3: Recompose the homepage around control-center sections

**Files:**
- Modify: `app/workbench/page.tsx`
- Modify: `components/overview/priority-cards.tsx`
- Modify: `components/overview/right-rail.tsx`
- Modify: `components/shared/metric-card.tsx`
- Modify: `components/shared/section-card.tsx`

- [ ] Step 1: Replace the current mixed homepage with hero, metrics, focus panels, operations entry cards, and lower-priority activity content.
- [ ] Step 2: Trim or restyle existing overview components so they fit the new hierarchy instead of the old dashboard layout.
- [ ] Step 3: Verify the page renders cleanly at desktop and tablet widths.

### Task 4: Verify the rework

**Files:**
- No code changes expected

- [ ] Step 1: Run `npm run test -- tests/unit/lib/selectors/overview.test.ts`.
- [ ] Step 2: Run `npm run typecheck`.
- [ ] Step 3: Run `npm run lint`.
- [ ] Step 4: If all pass, summarize the behavioral and visual changes with any residual risks.
