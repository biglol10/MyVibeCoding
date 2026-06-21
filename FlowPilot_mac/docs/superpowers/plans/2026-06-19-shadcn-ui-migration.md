# shadcn/ui Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace FlowPilot's custom CSS-heavy React UI with a shadcn/ui-style Tailwind/Radix component system while preserving all existing behavior.

**Architecture:** Add Tailwind v4 and shadcn-compatible UI primitives under `src/components/ui`, then migrate screens from layout primitives outward: app shell, cards, tables, forms, dialogs, and report controls. Keep Recharts and specialized chart math, but render chart panels and controls through the new design system.

**Tech Stack:** React 19, Vite 8, Tauri v2, Tailwind CSS v4, Radix UI primitives, class-variance-authority, tailwind-merge, lucide-react, Recharts, Vitest.

---

### Task 1: Foundation

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Modify: `vite.config.ts`
- Modify: `tsconfig.json`
- Modify: `tsconfig.app.json`
- Modify: `src/index.css`
- Create: `components.json`
- Create: `src/lib/utils.ts`

- [ ] Add Tailwind/Radix/shadcn dependencies.
- [ ] Configure Vite `tailwindcss()` plugin and `@/*` alias.
- [ ] Configure TypeScript `@/*` alias.
- [ ] Replace base CSS with Tailwind theme tokens and global desktop app defaults.
- [ ] Verify with `npm.cmd run build`.

### Task 2: UI Primitives

**Files:**
- Create: `src/components/ui/button.tsx`
- Create: `src/components/ui/card.tsx`
- Create: `src/components/ui/badge.tsx`
- Create: `src/components/ui/table.tsx`
- Create: `src/components/ui/input.tsx`
- Create: `src/components/ui/label.tsx`
- Create: `src/components/ui/select.tsx`
- Create: `src/components/ui/textarea.tsx`
- Create: `src/components/ui/dialog.tsx`
- Create: `src/components/ui/separator.tsx`
- Create: `src/components/ui/scroll-area.tsx`
- Create: `src/components/ui/tabs.tsx`

- [ ] Add shadcn-compatible primitives using Radix where appropriate.
- [ ] Keep components small and reusable.
- [ ] Verify with `npm.cmd test -- src/components/layout/AppShell.test.tsx`.

### Task 3: App Shell and Page Frame

**Files:**
- Modify: `src/components/layout/AppShell.tsx`
- Modify: `src/App.tsx`
- Modify: `src/components/reports/ReportRangePicker.tsx`

- [ ] Replace custom sidebar classes with Tailwind/shadcn button/card patterns.
- [ ] Replace loading/error/page header surfaces with shadcn cards.
- [ ] Replace range segment buttons and date fields with shadcn buttons/inputs.
- [ ] Verify app shell and app tests.

### Task 4: Dashboard and Tables

**Files:**
- Modify: `src/components/dashboard/TodaySummary.tsx`
- Modify: `src/components/dashboard/WeeklyTrends.tsx`
- Modify: `src/components/dashboard/DayTimeline.tsx`
- Modify: `src/components/dashboard/ActivityHeatmap.tsx`
- Modify: `src/components/tables/UsageTable.tsx`

- [ ] Convert summary cards, chart panels, timeline, heatmap, and usage tables to shadcn cards/tables/badges/buttons.
- [ ] Preserve chart data and accessibility labels.
- [ ] Verify dashboard/table tests.

### Task 5: Settings and Dialogs

**Files:**
- Modify: `src/components/rules/RulesSettings.tsx`
- Modify: `src/components/rules/UncategorizedReview.tsx`
- Modify: `src/components/displayNames/DisplayNameOverridesSettings.tsx`
- Modify: `src/components/groups/ActivityGroupsSettings.tsx`
- Modify: `src/components/sessions/SessionEditModal.tsx`

- [ ] Convert forms to shadcn labels/inputs/selects/buttons.
- [ ] Convert session edit modal to Radix Dialog.
- [ ] Convert settings tables to shadcn Table.
- [ ] Verify rules/group/display-name/session tests.

### Task 6: Cleanup and Verification

**Files:**
- Modify: `src/styles.css`
- Modify: `src/App.tsx`

- [ ] Remove broad custom component CSS after migration.
- [ ] Keep only chart/heatmap/timeline special styling that is clearer as CSS variables or Tailwind classes.
- [ ] Run `npm.cmd test`.
- [ ] Run `npm.cmd run build`.
- [ ] Sync to ASCII build path if Windows Tauri build is required.
- [ ] Run Rust tests and rebuild `dist-windows`.
