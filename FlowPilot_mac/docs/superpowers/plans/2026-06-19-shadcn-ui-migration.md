# shadcn UI Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace FlowPilot's custom React dashboard UI with a shadcn-compatible component system without changing app behavior.

**Architecture:** Add Tailwind plus local shadcn-style primitives in `src/components/ui`, then migrate existing feature components to compose those primitives. Keep all data loading, chart calculations, rules APIs, and navigation state unchanged.

**Tech Stack:** React 19, Vite, TypeScript, Tailwind CSS, class-variance-authority, tailwind-merge, lucide-react, Vitest.

---

### Task 1: Add Tailwind and shadcn Foundation

**Files:**
- Create: `components.json`
- Modify: `package.json`
- Modify: `src/index.css`
- Modify: `src/App.tsx`

- [ ] Add Tailwind, helper dependencies, and shadcn config.
- [ ] Move global theme variables into `src/index.css`.
- [ ] Keep `src/styles.css` temporarily during migration so each component can be moved safely.
- [ ] Run `npm test` and `npm run build`.

### Task 2: Add UI Primitives

**Files:**
- Create: `src/lib/utils.ts`
- Create: `src/components/ui/button.tsx`
- Create: `src/components/ui/card.tsx`
- Create: `src/components/ui/badge.tsx`
- Create: `src/components/ui/input.tsx`
- Create: `src/components/ui/select.tsx`
- Create: `src/components/ui/table.tsx`
- Create: `src/components/ui/alert.tsx`
- Create: `src/components/ui/progress.tsx`
- Create: `src/components/ui/separator.tsx`
- Create: `src/components/ui/button.test.tsx`

- [ ] Write a failing button variant test.
- [ ] Implement `cn` and primitives.
- [ ] Verify the new primitive test passes.
- [ ] Run `npm test`.

### Task 3: Migrate Layout and App States

**Files:**
- Modify: `src/components/layout/AppShell.tsx`
- Modify: `src/components/platform/MacosPermissionNotice.tsx`
- Modify: `src/App.tsx`

- [ ] Replace sidebar, nav buttons, status pill, permission notice, loading, and error panels with UI primitives.
- [ ] Preserve Korean labels and existing ARIA attributes.
- [ ] Run `npm test -- src/App.test.tsx src/components/layout/AppShell.test.tsx src/components/platform/MacosPermissionNotice.test.tsx`.

### Task 4: Migrate Dashboard Components

**Files:**
- Modify: `src/components/dashboard/TodaySummary.tsx`
- Modify: `src/components/dashboard/WeeklyTrends.tsx`
- Modify: `src/components/dashboard/DayTimeline.tsx`
- Modify: `src/pages/TodayPage.tsx`
- Modify: `src/pages/TimelinePage.tsx`
- Modify: `src/pages/WeeklyReportPage.tsx`

- [ ] Replace dashboard panels and metric cards with `Card` composition.
- [ ] Keep Recharts and timeline calculations unchanged.
- [ ] Run dashboard component tests.

### Task 5: Migrate Tables and Rule Workflows

**Files:**
- Modify: `src/components/tables/UsageTable.tsx`
- Modify: `src/components/rules/RulesSettings.tsx`
- Modify: `src/components/rules/UncategorizedReview.tsx`

- [ ] Replace raw table styling with `Table` primitives.
- [ ] Replace form controls with `Input`, `Select`, `Button`, `Badge`, and `Alert`.
- [ ] Preserve rule creation/editing behavior and disabled states.
- [ ] Run rules and table tests.

### Task 6: Remove Legacy CSS Surface

**Files:**
- Modify: `src/styles.css`
- Modify: `src/index.css`

- [ ] Remove migrated legacy selectors from `src/styles.css`.
- [ ] Keep only app-specific chart/timeline helpers that are not shadcn primitives.
- [ ] Ensure Tailwind classes cover layout, spacing, color, borders, typography, and states.
- [ ] Run `npm run build`.

### Task 7: Verify and Package

**Files:**
- No source files expected.

- [ ] Run `npm test`.
- [ ] Run `npm test` in `browser-extension`.
- [ ] Run `cargo test --manifest-path src-tauri/Cargo.toml`.
- [ ] Run `npm run build`.
- [ ] Start the app with `npm run tauri dev` and verify the UI renders.
- [ ] Commit the migration.
