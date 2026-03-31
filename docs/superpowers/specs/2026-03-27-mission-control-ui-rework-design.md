# Mission Control UI Rework Design

**Date:** 2026-03-27

**Goal:** Reframe OpenClaw Command Deck from a module-first dashboard into a mission-control operations surface that helps users judge system state, prioritize exceptions, and execute high-frequency actions without hunting through card grids.

## Context

The current frontend is a Next.js control console with a dark sidebar, light content area, and route-per-domain pages. The main shortcomings are structural rather than cosmetic:

- the homepage acts like a collection of modules instead of a decision surface
- information hierarchy is flat, so urgent items do not clearly dominate the first screen
- repeated card treatment makes primary actions, supporting signals, and background detail feel equally important
- navigation labels follow data domains, but do not reflect how an operator actually works through the product

The redesign should preserve the existing route model and server-side data loaders, but significantly change hierarchy, grouping, and visual language.

## Design Direction

### Visual Thesis

Mission control for a local AI operations product: dark anchored navigation, sharp status-led hero, pale operational surface, restrained teal accent, and stronger contrast between urgent work, supporting telemetry, and routine controls.

### Content Plan

1. Hero: current posture and next action
2. Support: priority queue and system pulse
3. Detail: quick actions and operational entry points
4. Continuation: lower-priority activity and secondary context

### Interaction Thesis

- staged entrance for hero, priority queue, and supporting panels
- stronger hover/state transitions on navigation and high-frequency action tiles
- compact motion only where it clarifies hierarchy or affordance

## Information Architecture

The application should shift from domain buckets to operator workflow buckets.

### Navigation Groups

- `Observe`
  - `/workbench`
  - `/alerts`
- `Act`
  - `/control`
  - `/sessions`
- `Operate`
  - `/channels`
  - `/cron`
  - `/agents`
- `Configure`
  - `/models`
  - `/settings`
  - `/diagnostics`

These groups do not change route ownership. They change how users understand where to look next.

## Homepage Structure

### 1. Posture Hero

The first screen should answer:

- is the system stable?
- what is the most important next step?
- what are the fastest relevant actions?

The hero should include:

- posture headline derived from health + priority count
- concise summary sentence
- status badge and supporting runtime context
- one or two direct actions

### 2. Priority Queue

This is the dominant operational block on the page. It should show only actionable exceptions, not all system facts. Each item should show:

- title
- source/category
- short summary
- recommended action
- visible urgency styling

### 3. System Pulse

This block supports judgement rather than action. It should summarize:

- channel availability
- cron health
- agent activity
- primary model/runtime posture where relevant

This area should be readable in seconds and visually lighter than the priority queue.

### 4. Quick Actions

High-frequency actions stay on the homepage, but appear after posture and triage. This prevents operational buttons from competing with urgent diagnosis.

### 5. Lower-Priority Continuation

Secondary items such as timelines, suggestions, and additional navigation cues can remain below the fold or in lower-contrast sections. They should no longer dominate the first screen.

## Shared Shell Changes

### Sidebar

The sidebar should become a stable anchor rather than a decorative block:

- product block with concise positioning copy
- connection status
- grouped workflow navigation
- clearer active state and calmer inactive state

### Top Header

The top area should align to page context:

- `workbench` uses the full posture hero presentation
- secondary pages default to compact page title + summary + status
- hidden header remains available for pages that need uninterrupted data tables

## Visual System

### Color

- dark navy sidebar/background anchor
- off-white operational canvas
- single teal accent family
- warning/critical tones reserved for status and queue emphasis

### Typography

- keep the current IBM Plex Sans-based tone unless implementation constraints require fallback
- larger, tighter headlines for posture statements
- smaller utility copy for operational labels and metadata

### Surfaces

- reduce blanket “card” usage
- use sectional grouping and tonal planes instead of wrapping everything in equal panels
- keep rounded surfaces, but assign them based on hierarchy rather than default repetition

## Page-Level Adaptation

This rework does not fully redesign every workflow page in one pass. It applies the new shell and hierarchy first, then updates the most visible operational pages to feel consistent.

### Workbench

Full mission-control composition.

### Alerts

Compact header, stronger priority framing, less generic paneling.

### Control

Compact header plus grouped action zones that inherit the new shell language.

### Remaining pages

Adopt the new shell, navigation grouping, spacing, and status styling first. Deeper workflow redesign can follow later if needed.

## Technical Boundaries

- preserve existing route paths
- preserve current data-loading entry points where possible
- prefer adapting existing overview/control components before introducing many new files
- keep implementation in plain CSS and existing React/Next patterns

## Validation Criteria

The redesign is successful if:

- the homepage clearly communicates system posture in the first screen
- a user can identify urgent work before seeing generic navigation or secondary metrics
- navigation groups reflect operator workflow more than backend domains
- shell changes propagate a stronger product identity across pages
- the UI feels more deliberate and less like a collection of interchangeable cards

## Constraints And Notes

- The current workspace is not a git repository, so this document cannot be committed here.
- Subagent-based document review is not available in this session because delegation was not explicitly requested by the user.
