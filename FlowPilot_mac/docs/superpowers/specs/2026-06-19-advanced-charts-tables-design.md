# Advanced Charts and Tables

Date: 2026-06-19
Status: Ready for user spec review

## Objective

Upgrade FlowPilot's charts and tables into a more capable desktop analytics experience without replacing the current shadcn-style visual system or destabilizing the macOS/Windows collector work.

The approved direction is option A:

- Keep Recharts as the chart engine and make the current charts more informative, polished, and consistent.
- Add TanStack Table as the headless table engine for sorting, filtering, row modeling, and future table controls.
- Keep shadcn-style primitives for the visible UI so the app still feels cohesive.

## Product Principles

- The app is an operational productivity tool, not a marketing dashboard. Prefer dense, scan-friendly surfaces over decorative visual complexity.
- Charts should explain activity status quickly: productive time, unproductive time, uncategorized work, idle time, and trends.
- Tables should help users inspect and act: sort, search, compare share/time, and understand which rule classified each item.
- Mobile and narrow desktop windows must remain usable. Rich tables should degrade into readable stacked rows or internal scroll, not page-level overflow.
- Do not change the underlying activity/session/rule data model for this UI pass.

## Library Choices

### Charts

Use the existing `recharts` dependency.

Enhancements:

- Shared chart card shell for consistent padding, border, empty state, and chart height.
- Shared tooltip content that formats durations, percentages, and category labels in Korean.
- Better chart metadata around the chart: totals, focus ratio, top category, and review-needed count.
- Improved legends that use the app's category colors and wrap predictably on small screens.
- More useful visual details: stacked bars, reference lines, active dots, axis formatting, and chart summaries.

Do not switch to Nivo, visx, or ECharts in this pass. Those can be evaluated in a separate future chart-engine migration, but they create unnecessary migration risk now.

### Tables

Add `@tanstack/react-table`.

Use it headlessly:

- Keep the current shadcn-style `Table`, `Badge`, `Button`, `Input`, and `Progress` components for rendering.
- Use TanStack row models for sorting and filtering.
- Keep table state local to each table component unless a future URL/state persistence requirement appears.

Do not add AG Grid or another heavy data-grid package in this pass. FlowPilot needs sorting, filtering, and better responsive rendering, not enterprise grid configuration.

## Scope

### Usage Tables

Upgrade `UsageTable` into a reusable analytics table:

- Sort by name, category, duration, share, and rule source.
- Default sort remains duration descending.
- Add a compact search field filtering app/domain names and matched rule source.
- Add a small row count summary in the card header or toolbar.
- Keep the existing progress bar for share, but make it fit consistently across table sizes.
- Add a responsive narrow layout so rows become stacked cards with labels instead of requiring horizontal page overflow.

### Rules Table

Use TanStack Table for the rules list in `RulesSettings`:

- Sort by name, rule type, pattern, category, priority, source.
- Filter by text across name and pattern.
- Keep add/edit/delete behavior unchanged.
- Keep built-in and user rule labels visible.
- Preserve existing tests around creating, editing, and deleting rules.

### Review Queue

Keep the newly improved narrow layout for `UncategorizedReview`.

- Keep quick classification buttons reachable on all viewport widths.
- Keep count and time metadata visible.
- Do not add sorting or filtering to the review queue in this pass.

### Today Summary Charts

Improve `TodaySummary`:

- Keep KPI cards, donut breakdown, and top destination bar chart.
- Replace ad hoc tooltip styling with shared tooltip content.
- Add chart-level summary text or badges for active total and focus ratio.
- Improve the top destinations chart so labels fit better on narrow widths.
- Preserve the current category color mapping.

### Weekly Trends

Improve `WeeklyTrends`:

- Keep stacked category bars plus productivity ratio line.
- Use shared tooltip and legend components.
- Add a 50% productivity reference line.
- Keep compact mode visually smaller while preserving readable labels.

## Components and Boundaries

New shared table helpers:

- `components/tables/AnalyticsTableToolbar.tsx`: search input and row count summary.
- `components/tables/tableFormatting.ts`: shared duration, share, and category formatting helpers.
- Existing `UsageTable.tsx` remains the public component consumed by pages.

New shared chart helpers:

- `components/charts/ChartCard.tsx`: chart shell for title, description, summary, and empty state.
- `components/charts/ChartTooltip.tsx`: Korean duration/percentage tooltip content.
- `components/charts/ChartLegend.tsx`: category legend layout for consistent wrapping.

Keep these helpers focused. They should not own app data fetching or classification logic.

## Data Flow

The page-level data flow remains unchanged:

1. `App.tsx` loads today's summary and sessions.
2. Pages pass sessions and summary into chart/table components.
3. Table components derive rows locally and apply TanStack sorting/filtering locally.
4. Chart components derive chart series locally and render Recharts with shared presentational helpers.
5. Rules and review actions continue to call existing API functions.

No persistence changes are required.

## Responsive Behavior

Desktop:

- Tables render as full tables with sortable headers.
- Toolbar appears above table content inside the card.
- Charts use full card width and fixed responsive height.

Narrow widths:

- Usage/rules tables must not cause document-level horizontal overflow.
- Usage rows should become stacked rows/cards if table columns would be unreadable.
- Chart legends wrap below the chart.
- Long app names, domains, URLs, and rule patterns use `overflow-wrap:anywhere`.

## Testing

Add or update frontend tests first:

- `UsageTable` renders sortable headers and defaults to duration descending.
- `UsageTable` filters rows by search text.
- `UsageTable` exposes a narrow-layout-friendly row/card contract.
- `RulesSettings` preserves create/edit/delete behavior after moving to TanStack Table.
- Chart components render formatted Korean tooltip/legend content through testable helpers.
- Empty states still render when data is absent.

Existing tests that must continue passing:

- App navigation and rule refresh tests.
- Today summary tests.
- Weekly trends tests.
- Rules settings tests.
- Uncategorized review tests.
- Browser extension tests.
- Rust tests.

## Verification

Run these before completion:

```bash
npm test
npm run build
npm test --prefix browser-extension
source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml
npm run package:macos
```

For visual verification:

- Run the local app and capture desktop and narrow-width screenshots for Today, Weekly Report, Timeline, Review, and Rules.
- Confirm no page-level horizontal overflow.
- Confirm sortable/filterable tables have usable controls and no clipped text.
- Confirm chart labels, legends, and tooltips fit the available space.

## Out of Scope

- Replacing Recharts with another chart engine.
- Adding AG Grid or a paid/enterprise-style data grid.
- Persisting table sort/filter preferences.
- Adding pagination unless real datasets become large enough to require it.
- Changing collector logic, classification rules, or storage schema.
- Reworking the whole navigation or page architecture.
