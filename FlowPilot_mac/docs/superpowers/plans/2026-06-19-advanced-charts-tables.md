# Advanced Charts and Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade FlowPilot charts and tables with Recharts polish and TanStack Table behavior while preserving the existing shadcn-style UI and collector behavior.

**Architecture:** Keep page data loading unchanged. Add small presentation helpers for chart shells/tooltips/legends, and use TanStack Table locally inside table components for sorting and filtering. Existing API, Rust, storage, collector, and classification logic remain unchanged.

**Tech Stack:** React 19, TypeScript, Tauri v2, Recharts, shadcn-style local components, `@tanstack/react-table`, Vitest, Testing Library, Playwright-style screenshot checks.

---

## Current Worktree Note

The worktree may already contain unrelated uncommitted files from previous UI/package fixes:

- `docs/macos-development.md`
- `src-tauri/tauri.conf.json`
- `src/components/rules/UncategorizedReview.test.tsx`
- `src/components/rules/UncategorizedReview.tsx`
- `src/components/ui/card.tsx`

Do not revert or overwrite those changes. Commit only the files touched by each task.

## References

- Spec: `docs/superpowers/specs/2026-06-19-advanced-charts-tables-design.md`
- TanStack React adapter: `https://tanstack.com/table/latest/docs/framework/react/react-table`
- TanStack column definitions: `https://tanstack.com/table/latest/docs/guide/column-defs`
- TanStack sorting: `https://tanstack.com/table/latest/docs/guide/sorting`
- TanStack global filtering: `https://tanstack.com/table/latest/docs/guide/global-filtering`

## File Structure

Create:

- `src/components/tables/AnalyticsTableToolbar.tsx`: reusable table search and row-count toolbar.
- `src/components/tables/SortableTableHead.tsx`: sortable shadcn table header button.
- `src/components/tables/tableFormatting.ts`: shared table labels and formatting helpers.
- `src/components/charts/ChartTooltip.tsx`: Recharts tooltip content with Korean labels and duration formatting.
- `src/components/charts/ChartLegend.tsx`: compact wrapping category legend.
- `src/components/charts/ChartPanel.tsx`: consistent chart surface and empty state wrapper.
- `src/components/charts/ChartTooltip.test.tsx`
- `src/components/charts/ChartLegend.test.tsx`
- `src/components/tables/AnalyticsTableToolbar.test.tsx`
- `src/components/tables/SortableTableHead.test.tsx`

Modify:

- `package.json`
- `package-lock.json`
- `src/components/tables/UsageTable.tsx`
- `src/components/tables/UsageTable.test.tsx`
- `src/components/rules/RulesSettings.tsx`
- `src/components/rules/RulesSettings.test.tsx`
- `src/components/dashboard/TodaySummary.tsx`
- `src/components/dashboard/TodaySummary.test.tsx`
- `src/components/dashboard/WeeklyTrends.tsx`
- `src/components/dashboard/WeeklyTrends.test.tsx`
- `src/styles.css` only if Recharts global tooltip styling becomes redundant after helper migration.

---

### Task 1: Add TanStack Table Dependency

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`

- [ ] **Step 1: Install dependency**

Run:

```bash
npm install @tanstack/react-table
```

Expected:

- `package.json` has `@tanstack/react-table` under `dependencies`.
- `package-lock.json` is updated.

- [ ] **Step 2: Verify install did not break existing tests**

Run:

```bash
npm test
```

Expected: all existing frontend tests pass.

- [ ] **Step 3: Commit**

Run:

```bash
git add package.json package-lock.json
git commit -m "chore: add tanstack table"
```

Expected: commit contains only dependency files.

---

### Task 2: Add Shared Table UI Helpers

**Files:**
- Create: `src/components/tables/AnalyticsTableToolbar.tsx`
- Create: `src/components/tables/AnalyticsTableToolbar.test.tsx`
- Create: `src/components/tables/SortableTableHead.tsx`
- Create: `src/components/tables/SortableTableHead.test.tsx`
- Create: `src/components/tables/tableFormatting.ts`

- [ ] **Step 1: Write failing toolbar tests**

Create `src/components/tables/AnalyticsTableToolbar.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AnalyticsTableToolbar } from "./AnalyticsTableToolbar";

describe("AnalyticsTableToolbar", () => {
  it("renders Korean search control and row count", async () => {
    const user = userEvent.setup();
    const onSearchChange = vi.fn();

    render(
      <AnalyticsTableToolbar
        searchLabel="사용 항목 검색"
        searchPlaceholder="앱 또는 도메인 검색"
        searchValue=""
        onSearchChange={onSearchChange}
        visibleRows={2}
        totalRows={5}
      />,
    );

    expect(screen.getByText("2 / 5개 표시")).toBeInTheDocument();
    await user.type(screen.getByLabelText("사용 항목 검색"), "chat");
    expect(onSearchChange).toHaveBeenLastCalledWith("chat");
  });
});
```

- [ ] **Step 2: Write failing sortable header tests**

Create `src/components/tables/SortableTableHead.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SortableTableHead } from "./SortableTableHead";

describe("SortableTableHead", () => {
  it("announces descending sort state and calls toggle handler", async () => {
    const user = userEvent.setup();
    const toggleSorting = vi.fn();

    render(
      <table>
        <thead>
          <tr>
            <SortableTableHead
              canSort
              label="시간"
              sortState="desc"
              toggleSorting={toggleSorting}
            />
          </tr>
        </thead>
      </table>,
    );

    const button = screen.getByRole("button", { name: "시간 내림차순 정렬됨" });
    await user.click(button);
    expect(toggleSorting).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
npm test -- AnalyticsTableToolbar.test.tsx SortableTableHead.test.tsx
```

Expected: both test files fail because the components do not exist.

- [ ] **Step 4: Implement `AnalyticsTableToolbar`**

Create `src/components/tables/AnalyticsTableToolbar.tsx`:

```tsx
import { Input } from "../ui/input";

interface AnalyticsTableToolbarProps {
  onSearchChange: (value: string) => void;
  searchLabel: string;
  searchPlaceholder: string;
  searchValue: string;
  totalRows: number;
  visibleRows: number;
}

export function AnalyticsTableToolbar({
  onSearchChange,
  searchLabel,
  searchPlaceholder,
  searchValue,
  totalRows,
  visibleRows,
}: AnalyticsTableToolbarProps) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-b px-5 py-3">
      <label className="grid min-w-[220px] flex-1 gap-1.5 text-xs font-semibold text-muted-foreground">
        <span>{searchLabel}</span>
        <Input
          value={searchValue}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder={searchPlaceholder}
          type="search"
        />
      </label>
      <span className="rounded-md border bg-muted/35 px-2.5 py-1 text-xs font-semibold text-muted-foreground">
        {visibleRows} / {totalRows}개 표시
      </span>
    </div>
  );
}
```

- [ ] **Step 5: Implement `SortableTableHead`**

Create `src/components/tables/SortableTableHead.tsx`:

```tsx
import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { Button } from "../ui/button";
import { TableHead } from "../ui/table";

type SortState = false | "asc" | "desc";

interface SortableTableHeadProps {
  canSort: boolean;
  className?: string;
  label: string;
  sortState: SortState;
  toggleSorting: () => void;
}

function sortLabel(label: string, sortState: SortState): string {
  if (sortState === "asc") {
    return `${label} 오름차순 정렬됨`;
  }

  if (sortState === "desc") {
    return `${label} 내림차순 정렬됨`;
  }

  return `${label} 정렬`;
}

export function SortableTableHead({
  canSort,
  className,
  label,
  sortState,
  toggleSorting,
}: SortableTableHeadProps) {
  if (!canSort) {
    return (
      <TableHead className={className} scope="col">
        {label}
      </TableHead>
    );
  }

  const Icon = sortState === "asc" ? ArrowUp : sortState === "desc" ? ArrowDown : ChevronsUpDown;

  return (
    <TableHead className={className} scope="col">
      <Button
        aria-label={sortLabel(label, sortState)}
        className="-ml-3 h-8 px-2 text-xs uppercase text-muted-foreground"
        onClick={toggleSorting}
        size="sm"
        type="button"
        variant="ghost"
      >
        {label}
        <Icon aria-hidden="true" className="size-3.5" />
      </Button>
    </TableHead>
  );
}
```

- [ ] **Step 6: Implement table formatting helpers**

Create `src/components/tables/tableFormatting.ts`:

```ts
import { CATEGORY_LABELS, RULE_SOURCE_LABELS } from "../../lib/labels";
import type { ProductivityCategory } from "../../types/activity";

export function displayRuleSource(matchedRuleId: string | null): string {
  if (!matchedRuleId) {
    return RULE_SOURCE_LABELS.none;
  }

  if (matchedRuleId.startsWith("builtin:")) {
    return RULE_SOURCE_LABELS.builtin;
  }

  if (matchedRuleId.startsWith("user:")) {
    return RULE_SOURCE_LABELS.custom;
  }

  return matchedRuleId;
}

export function displayCategory(category: ProductivityCategory, isIdle = false): string {
  return isIdle ? "유휴" : CATEGORY_LABELS[category];
}
```

- [ ] **Step 7: Run helper tests**

Run:

```bash
npm test -- AnalyticsTableToolbar.test.tsx SortableTableHead.test.tsx
```

Expected: both test files pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add src/components/tables/AnalyticsTableToolbar.tsx src/components/tables/AnalyticsTableToolbar.test.tsx src/components/tables/SortableTableHead.tsx src/components/tables/SortableTableHead.test.tsx src/components/tables/tableFormatting.ts
git commit -m "feat: add analytics table helpers"
```

Expected: commit contains only shared table helper files.

---

### Task 3: Upgrade `UsageTable` with TanStack Sorting, Search, and Narrow Rows

**Files:**
- Modify: `src/components/tables/UsageTable.tsx`
- Modify: `src/components/tables/UsageTable.test.tsx`

- [ ] **Step 1: Add failing `UsageTable` behavior tests**

Append these tests to `src/components/tables/UsageTable.test.tsx`:

```tsx
import userEvent from "@testing-library/user-event";

it("defaults to duration descending and can sort by name", async () => {
  const user = userEvent.setup();
  render(
    <UsageTable
      sessions={[
        session({ id: "short", domain: "zeta.com", durationSeconds: 60 }),
        session({ id: "long", domain: "alpha.com", durationSeconds: 600 }),
      ]}
    />,
  );

  const initialRows = screen.getAllByRole("row");
  expect(within(initialRows[1]).getByText("alpha.com")).toBeInTheDocument();
  expect(within(initialRows[2]).getByText("zeta.com")).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "이름 정렬" }));

  const sortedRows = screen.getAllByRole("row");
  expect(within(sortedRows[1]).getByText("alpha.com")).toBeInTheDocument();
  expect(within(sortedRows[2]).getByText("zeta.com")).toBeInTheDocument();
});

it("filters rows by search text and reports visible row count", async () => {
  const user = userEvent.setup();
  render(
    <UsageTable
      sessions={[
        session({ id: "chat", domain: "chatgpt.com", durationSeconds: 600 }),
        session({ id: "video", domain: "youtube.com", durationSeconds: 300 }),
      ]}
    />,
  );

  await user.type(screen.getByLabelText("사용 항목 검색"), "chat");

  expect(screen.getByText("1 / 2개 표시")).toBeInTheDocument();
  expect(screen.getByText("chatgpt.com")).toBeInTheDocument();
  expect(screen.queryByText("youtube.com")).not.toBeInTheDocument();
});

it("marks table rows with a narrow-layout card class", () => {
  render(<UsageTable sessions={[session({ domain: "chatgpt.com" })]} />);

  const row = screen.getByRole("row", { name: /chatgpt\.com/i });
  expect(row).toHaveClass("max-[640px]:block");
  expect(screen.getByText("비중")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
npm test -- UsageTable.test.tsx
```

Expected: new tests fail because sorting/search/narrow classes are not implemented.

- [ ] **Step 3: Replace `UsageTable` with TanStack implementation**

Modify `src/components/tables/UsageTable.tsx` using this structure:

```tsx
import { useMemo, useState } from "react";
import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  type SortingState,
  useReactTable,
} from "@tanstack/react-table";
import { colorForCategory } from "../../lib/colors";
import { EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory } from "../../types/activity";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { Progress } from "../ui/progress";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { AnalyticsTableToolbar } from "./AnalyticsTableToolbar";
import { SortableTableHead } from "./SortableTableHead";
import { displayCategory, displayRuleSource } from "./tableFormatting";
```

Keep the existing `UsageTableProps`, `UsageRow`, `displayName`, `dominantCategory`, and `buildRows`, but remove the local `displayRule` function and use `displayRuleSource`.

Add:

```tsx
const columnHelper = createColumnHelper<UsageRow>();

function rowSearchText(row: UsageRow): string {
  return [
    row.name,
    displayCategory(row.category, row.isIdle),
    displayRuleSource(row.matchedRule),
    formatDuration(row.durationSeconds),
    `${Math.round(row.share * 100)}%`,
  ]
    .join(" ")
    .toLowerCase();
}
```

Inside `UsageTable`, replace the current `rows` constant and table rendering setup with:

```tsx
const rows = useMemo(
  () => buildRows(sessions).slice(0, maxRows ?? Number.POSITIVE_INFINITY),
  [maxRows, sessions],
);
const [globalFilter, setGlobalFilter] = useState("");
const [sorting, setSorting] = useState<SortingState>([{ id: "durationSeconds", desc: true }]);
const columns = useMemo(
  () => [
    columnHelper.accessor("name", {
      header: "이름",
      cell: (info) => {
        const row = info.row.original;
        const color = colorForCategory(row.category, row.isIdle);
        return (
          <span className="inline-flex max-w-60 items-center gap-2 [overflow-wrap:anywhere]">
            <i className="size-2.5 shrink-0 rounded-sm" style={{ backgroundColor: color }} />
            {info.getValue()}
          </span>
        );
      },
    }),
    columnHelper.accessor((row) => displayCategory(row.category, row.isIdle), {
      id: "categoryLabel",
      header: "분류",
      cell: (info) => {
        const row = info.row.original;
        const color = colorForCategory(row.category, row.isIdle);
        return (
          <Badge className="border bg-white" style={{ borderColor: color, color }} variant="outline">
            {info.getValue()}
          </Badge>
        );
      },
    }),
    columnHelper.accessor("durationSeconds", {
      header: "시간",
      cell: (info) => <span className="font-medium">{formatDuration(info.getValue())}</span>,
      sortingFn: "basic",
    }),
    columnHelper.accessor("share", {
      header: "비중",
      cell: (info) => {
        const row = info.row.original;
        const color = colorForCategory(row.category, row.isIdle);
        const sharePercent = Math.round(info.getValue() * 100);
        return (
          <span className="inline-grid min-w-32 grid-cols-[82px_auto] items-center gap-2 max-[640px]:min-w-0 max-[640px]:grid-cols-[minmax(0,1fr)_auto]">
            <Progress
              aria-label={`${sharePercent}퍼센트`}
              className="h-2"
              indicatorStyle={{ backgroundColor: color }}
              value={sharePercent}
            />
            <span className="text-sm font-semibold text-muted-foreground">{sharePercent}%</span>
          </span>
        );
      },
      sortingFn: "basic",
    }),
    columnHelper.accessor((row) => displayRuleSource(row.matchedRule), {
      id: "ruleSource",
      header: "적용 규칙",
      cell: (info) => <span className="max-w-60 [overflow-wrap:anywhere] text-muted-foreground">{info.getValue()}</span>,
    }),
  ],
  [],
);
const table = useReactTable({
  columns,
  data: rows,
  getCoreRowModel: getCoreRowModel(),
  getFilteredRowModel: getFilteredRowModel(),
  getSortedRowModel: getSortedRowModel(),
  globalFilterFn: (row, _columnId, filterValue) => {
    return rowSearchText(row.original).includes(String(filterValue).trim().toLowerCase());
  },
  onGlobalFilterChange: setGlobalFilter,
  onSortingChange: setSorting,
  state: { globalFilter, sorting },
});
const visibleRows = table.getRowModel().rows;
```

Render the toolbar before the table:

```tsx
<AnalyticsTableToolbar
  searchLabel="사용 항목 검색"
  searchPlaceholder="앱, 도메인, 규칙 검색"
  searchValue={globalFilter}
  onSearchChange={setGlobalFilter}
  totalRows={rows.length}
  visibleRows={visibleRows.length}
/>
```

Render headers through `SortableTableHead`:

```tsx
{table.getHeaderGroups().map((headerGroup) => (
  <TableRow key={headerGroup.id}>
    {headerGroup.headers.map((header) => (
      <SortableTableHead
        key={header.id}
        canSort={header.column.getCanSort()}
        label={String(header.column.columnDef.header)}
        sortState={header.column.getIsSorted()}
        toggleSorting={header.column.getToggleSortingHandler()}
      />
    ))}
  </TableRow>
))}
```

Render rows with narrow labels:

```tsx
{visibleRows.map((row) => (
  <TableRow className="max-[640px]:block max-[640px]:p-5" key={row.id}>
    {row.getVisibleCells().map((cell) => (
      <TableCell
        className="max-[640px]:mt-3 max-[640px]:flex max-[640px]:items-center max-[640px]:justify-between max-[640px]:gap-4 max-[640px]:p-0"
        key={cell.id}
      >
        <span className="hidden text-xs font-semibold text-muted-foreground max-[640px]:inline">
          {String(cell.column.columnDef.header)}
        </span>
        <span className="min-w-0 text-right max-[640px]:text-left">
          {flexRender(cell.column.columnDef.cell, cell.getContext())}
        </span>
      </TableCell>
    ))}
  </TableRow>
))}
```

If `rows.length > 0` but `visibleRows.length === 0`, render:

```tsx
<TableRow>
  <TableCell className="h-32 text-center text-sm font-semibold text-muted-foreground" colSpan={columns.length}>
    검색 결과가 없습니다.
  </TableCell>
</TableRow>
```

- [ ] **Step 4: Run `UsageTable` tests**

Run:

```bash
npm test -- UsageTable.test.tsx
```

Expected: all `UsageTable` tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add src/components/tables/UsageTable.tsx src/components/tables/UsageTable.test.tsx
git commit -m "feat: upgrade usage table interactions"
```

Expected: commit contains only `UsageTable` implementation and tests.

---

### Task 4: Upgrade `RulesSettings` Table with TanStack Sorting and Search

**Files:**
- Modify: `src/components/rules/RulesSettings.tsx`
- Modify: `src/components/rules/RulesSettings.test.tsx`

- [ ] **Step 1: Add failing `RulesSettings` tests**

Append these tests to `src/components/rules/RulesSettings.test.tsx`:

```tsx
it("filters rules by name or pattern", async () => {
  const user = userEvent.setup();
  vi.mocked(listRules).mockResolvedValue([
    existingRule,
    { ...createdRule, id: "user:urlPattern:/shorts", name: "/shorts", pattern: "/shorts" },
  ]);
  render(<RulesSettings />);

  await screen.findByText("ChatGPT");
  await user.type(screen.getByLabelText("규칙 검색"), "shorts");

  expect(screen.getByText("1 / 2개 표시")).toBeInTheDocument();
  expect(screen.getByRole("row", { name: /shorts/ })).toBeInTheDocument();
  expect(screen.queryByRole("row", { name: /ChatGPT/ })).not.toBeInTheDocument();
});

it("sorts rules by priority", async () => {
  const user = userEvent.setup();
  vi.mocked(listRules).mockResolvedValue([
    { ...createdRule, priority: 100 },
    { ...existingRule, priority: 0 },
  ]);
  render(<RulesSettings />);

  await screen.findByText("ChatGPT");
  await user.click(screen.getByRole("button", { name: "우선순위 정렬" }));

  const rows = screen.getAllByRole("row");
  expect(within(rows[1]).getByText("ChatGPT")).toBeInTheDocument();
  expect(within(rows[2]).getAllByText("/watch")).toHaveLength(2);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
npm test -- RulesSettings.test.tsx
```

Expected: new tests fail because the rules toolbar and sortable headers are not implemented.

- [ ] **Step 3: Import TanStack and helpers**

Modify imports in `src/components/rules/RulesSettings.tsx`:

```tsx
import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  type SortingState,
  useReactTable,
} from "@tanstack/react-table";
import { AnalyticsTableToolbar } from "../tables/AnalyticsTableToolbar";
import { SortableTableHead } from "../tables/SortableTableHead";
```

- [ ] **Step 4: Add rule table helpers**

Add below constants:

```tsx
const columnHelper = createColumnHelper<ClassificationRule>();

function ruleSource(rule: ClassificationRule): string {
  return rule.isBuiltin ? RULE_SOURCE_LABELS.builtin : RULE_SOURCE_LABELS.custom;
}

function ruleSearchText(rule: ClassificationRule): string {
  return [
    rule.name,
    rule.pattern,
    RULE_TYPE_LABELS[rule.ruleType],
    CATEGORY_LABELS[rule.category],
    ruleSource(rule),
    String(rule.priority),
  ]
    .join(" ")
    .toLowerCase();
}
```

- [ ] **Step 5: Create table instance in `RulesSettings`**

After `const rules = ...`, add:

```tsx
const [globalFilter, setGlobalFilter] = useState("");
const [sorting, setSorting] = useState<SortingState>([{ id: "priority", desc: false }]);
const columns = useMemo(
  () => [
    columnHelper.accessor("name", {
      header: "이름",
      cell: (info) => <span className="font-semibold text-foreground">{info.getValue()}</span>,
    }),
    columnHelper.accessor((rule) => RULE_TYPE_LABELS[rule.ruleType], {
      id: "ruleTypeLabel",
      header: "종류",
    }),
    columnHelper.accessor("pattern", {
      header: "패턴",
      cell: (info) => <span className="max-w-60 [overflow-wrap:anywhere] text-muted-foreground">{info.getValue()}</span>,
    }),
    columnHelper.accessor((rule) => CATEGORY_LABELS[rule.category], {
      id: "categoryLabel",
      header: "분류",
      cell: (info) => {
        const rule = info.row.original;
        return <Badge variant={rule.category === "productive" ? "default" : "secondary"}>{info.getValue()}</Badge>;
      },
    }),
    columnHelper.accessor("priority", {
      header: "우선순위",
      sortingFn: "basic",
    }),
    columnHelper.accessor(ruleSource, {
      id: "source",
      header: "출처",
    }),
    columnHelper.display({
      id: "actions",
      header: "관리",
      cell: (info) => (
        <Button size="sm" type="button" onClick={() => handleEditRule(info.row.original)} variant="outline">
          수정
        </Button>
      ),
      enableSorting: false,
    }),
  ],
  [],
);
const table = useReactTable({
  columns,
  data: rules,
  getCoreRowModel: getCoreRowModel(),
  getFilteredRowModel: getFilteredRowModel(),
  getSortedRowModel: getSortedRowModel(),
  globalFilterFn: (row, _columnId, filterValue) => {
    return ruleSearchText(row.original).includes(String(filterValue).trim().toLowerCase());
  },
  onGlobalFilterChange: setGlobalFilter,
  onSortingChange: setSorting,
  state: { globalFilter, sorting },
});
const visibleRows = table.getRowModel().rows;
```

If TypeScript complains that `handleEditRule` changes identity, leave `columns` without memoization or include `handleEditRule` in the dependency array. Do not change edit behavior.

- [ ] **Step 6: Replace rules table rendering**

In the ready/rules block, insert toolbar before the table:

```tsx
<AnalyticsTableToolbar
  searchLabel="규칙 검색"
  searchPlaceholder="이름, 패턴, 출처 검색"
  searchValue={globalFilter}
  onSearchChange={setGlobalFilter}
  totalRows={rules.length}
  visibleRows={visibleRows.length}
/>
```

Render header:

```tsx
{table.getHeaderGroups().map((headerGroup) => (
  <TableRow key={headerGroup.id}>
    {headerGroup.headers.map((header) => (
      <SortableTableHead
        key={header.id}
        canSort={header.column.getCanSort()}
        label={String(header.column.columnDef.header)}
        sortState={header.column.getIsSorted()}
        toggleSorting={header.column.getToggleSortingHandler()}
      />
    ))}
  </TableRow>
))}
```

Render body:

```tsx
{visibleRows.length > 0 ? (
  visibleRows.map((row) => (
    <TableRow className="max-[640px]:block max-[640px]:p-5" key={row.id}>
      {row.getVisibleCells().map((cell) => (
        <TableCell
          className="max-[640px]:mt-3 max-[640px]:flex max-[640px]:items-center max-[640px]:justify-between max-[640px]:gap-4 max-[640px]:p-0"
          key={cell.id}
        >
          <span className="hidden text-xs font-semibold text-muted-foreground max-[640px]:inline">
            {String(cell.column.columnDef.header)}
          </span>
          <span className="min-w-0 text-right max-[640px]:text-left">
            {flexRender(cell.column.columnDef.cell, cell.getContext())}
          </span>
        </TableCell>
      ))}
    </TableRow>
  ))
) : (
  <TableRow>
    <TableCell className="h-32 text-center text-sm font-semibold text-muted-foreground" colSpan={columns.length}>
      검색 결과가 없습니다.
    </TableCell>
  </TableRow>
)}
```

- [ ] **Step 7: Run tests**

Run:

```bash
npm test -- RulesSettings.test.tsx
```

Expected: all `RulesSettings` tests pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add src/components/rules/RulesSettings.tsx src/components/rules/RulesSettings.test.tsx
git commit -m "feat: upgrade rules table interactions"
```

Expected: commit contains only `RulesSettings` table changes and tests.

---

### Task 5: Add Shared Chart Helpers

**Files:**
- Create: `src/components/charts/ChartPanel.tsx`
- Create: `src/components/charts/ChartTooltip.tsx`
- Create: `src/components/charts/ChartTooltip.test.tsx`
- Create: `src/components/charts/ChartLegend.tsx`
- Create: `src/components/charts/ChartLegend.test.tsx`

- [ ] **Step 1: Write failing chart tooltip test**

Create `src/components/charts/ChartTooltip.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { ChartTooltip } from "./ChartTooltip";

describe("ChartTooltip", () => {
  it("formats durations and productivity ratio in Korean", () => {
    render(
      <ChartTooltip
        active
        label="금"
        payload={[
          { name: "productive", value: 2700, color: "#16a34a" },
          { name: "ratio", value: 60, color: "#111827" },
        ]}
      />,
    );

    expect(screen.getByText("금")).toBeInTheDocument();
    expect(screen.getByText("생산적")).toBeInTheDocument();
    expect(screen.getByText("45m")).toBeInTheDocument();
    expect(screen.getByText("생산성 비율")).toBeInTheDocument();
    expect(screen.getByText("60%")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Write failing chart legend test**

Create `src/components/charts/ChartLegend.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { ChartLegend } from "./ChartLegend";

describe("ChartLegend", () => {
  it("renders wrapping legend entries", () => {
    render(
      <ChartLegend
        items={[
          { label: "생산적", color: "#16a34a" },
          { label: "비생산", color: "#dc2626" },
        ]}
      />,
    );

    expect(screen.getByText("생산적")).toBeInTheDocument();
    expect(screen.getByText("비생산")).toBeInTheDocument();
    expect(screen.getByLabelText("차트 범례")).toHaveClass("flex-wrap");
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
npm test -- ChartTooltip.test.tsx ChartLegend.test.tsx
```

Expected: tests fail because chart helper components do not exist.

- [ ] **Step 4: Implement `ChartTooltip`**

Create `src/components/charts/ChartTooltip.tsx`:

```tsx
import { CATEGORY_LABELS } from "../../lib/labels";
import { formatDuration } from "../../lib/time";

interface TooltipPayloadItem {
  color?: string;
  name?: string | number;
  value?: string | number;
}

interface ChartTooltipProps {
  active?: boolean;
  label?: string | number;
  payload?: TooltipPayloadItem[];
}

function labelForName(name: string | number | undefined): string {
  if (name === "ratio") {
    return "생산성 비율";
  }

  if (name === "idle") {
    return "유휴";
  }

  const key = String(name ?? "");
  return CATEGORY_LABELS[key as keyof typeof CATEGORY_LABELS] ?? key;
}

function valueForName(name: string | number | undefined, value: string | number | undefined): string {
  const numericValue = Number(value ?? 0);
  if (name === "ratio") {
    return `${numericValue}%`;
  }

  return formatDuration(numericValue);
}

export function ChartTooltip({ active, label, payload }: ChartTooltipProps) {
  if (!active || !payload?.length) {
    return null;
  }

  return (
    <div className="rounded-lg border bg-popover p-3 text-sm text-popover-foreground shadow-md">
      {label ? <p className="mb-2 font-semibold">{label}</p> : null}
      <div className="grid gap-1.5">
        {payload.map((item) => (
          <div className="flex min-w-36 items-center justify-between gap-4" key={`${item.name}-${item.value}`}>
            <span className="inline-flex min-w-0 items-center gap-2 text-muted-foreground">
              <i className="size-2.5 shrink-0 rounded-sm" style={{ backgroundColor: item.color ?? "currentColor" }} />
              {labelForName(item.name)}
            </span>
            <strong>{valueForName(item.name, item.value)}</strong>
          </div>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Implement `ChartLegend`**

Create `src/components/charts/ChartLegend.tsx`:

```tsx
interface ChartLegendItem {
  color: string;
  label: string;
}

interface ChartLegendProps {
  items: ChartLegendItem[];
}

export function ChartLegend({ items }: ChartLegendProps) {
  if (items.length === 0) {
    return null;
  }

  return (
    <div aria-label="차트 범례" className="flex flex-wrap gap-x-3 gap-y-2 px-1 text-xs font-semibold text-muted-foreground">
      {items.map((item) => (
        <span className="inline-flex items-center gap-1.5" key={item.label}>
          <i className="size-2.5 rounded-sm" style={{ backgroundColor: item.color }} />
          {item.label}
        </span>
      ))}
    </div>
  );
}
```

- [ ] **Step 6: Implement `ChartPanel`**

Create `src/components/charts/ChartPanel.tsx`:

```tsx
import type { ReactNode } from "react";
import { cn } from "../../lib/utils";

interface ChartPanelProps {
  ariaLabel: string;
  children: ReactNode;
  className?: string;
}

export function ChartPanel({ ariaLabel, children, className }: ChartPanelProps) {
  return (
    <div
      aria-label={ariaLabel}
      className={cn("min-h-[250px] rounded-lg border bg-gradient-to-b from-card to-muted/30 p-3", className)}
      role="img"
    >
      {children}
    </div>
  );
}
```

- [ ] **Step 7: Run helper tests**

Run:

```bash
npm test -- ChartTooltip.test.tsx ChartLegend.test.tsx
```

Expected: chart helper tests pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add src/components/charts/ChartPanel.tsx src/components/charts/ChartTooltip.tsx src/components/charts/ChartTooltip.test.tsx src/components/charts/ChartLegend.tsx src/components/charts/ChartLegend.test.tsx
git commit -m "feat: add chart presentation helpers"
```

Expected: commit contains only chart helper files.

---

### Task 6: Polish `TodaySummary` Charts

**Files:**
- Modify: `src/components/dashboard/TodaySummary.tsx`
- Modify: `src/components/dashboard/TodaySummary.test.tsx`

- [ ] **Step 1: Add failing tests**

Update the Recharts mock in `TodaySummary.test.tsx` so `Tooltip` exposes custom content:

```tsx
  Tooltip: ({ content }: { content?: ReactNode }) => <div>{content}</div>,
```

Add:

```tsx
it("renders chart summaries and shared legend labels", () => {
  render(
    <TodaySummary
      sessions={[session({ id: "chat", domain: "chatgpt.com", durationSeconds: 900 })]}
      summary={{ ...emptySummary, productiveSeconds: 900, trackedSeconds: 900 }}
    />,
  );

  expect(screen.getByText("활동 합계")).toBeInTheDocument();
  expect(screen.getByText("생산성 비율")).toBeInTheDocument();
  expect(screen.getByLabelText("차트 범례")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- TodaySummary.test.tsx
```

Expected: the new summary/legend assertions fail.

- [ ] **Step 3: Import chart helpers**

Modify imports in `TodaySummary.tsx`:

```tsx
import { ChartLegend } from "../charts/ChartLegend";
import { ChartPanel } from "../charts/ChartPanel";
import { ChartTooltip } from "../charts/ChartTooltip";
```

- [ ] **Step 4: Replace ad hoc chart containers**

Replace the donut panel wrapper with:

```tsx
<ChartPanel ariaLabel="생산성 분류 도넛 차트">
  <div className="mb-2 grid grid-cols-2 gap-2 text-xs font-semibold text-muted-foreground">
    <span>활동 합계</span>
    <span className="text-right">{formatDuration(activeTotal)}</span>
    <span>생산성 비율</span>
    <span className="text-right">{focusRatio}</span>
  </div>
  ...
  <ChartLegend items={breakdown.map((entry) => ({ label: entry.name, color: entry.color }))} />
</ChartPanel>
```

Keep the existing donut gradient and empty state inside the panel.

Replace the destination chart panel with:

```tsx
<ChartPanel ariaLabel="상위 사용 항목 막대 차트" className="p-2">
  {topDestinations.length > 0 ? (
    <ResponsiveContainer width="100%" height={230}>
      <BarChart data={topDestinations} margin={{ top: 12, right: 12, bottom: 0, left: -12 }}>
        <CartesianGrid strokeDasharray="3 3" vertical={false} />
        <XAxis dataKey="name" tickLine={false} axisLine={false} tickMargin={8} interval={0} />
        <YAxis tickFormatter={(value) => formatDuration(Number(value))} tickLine={false} axisLine={false} width={52} />
        <Tooltip content={<ChartTooltip />} />
        <Bar dataKey="seconds" name="사용 시간" radius={[6, 6, 0, 0]}>
          {topDestinations.map((entry) => (
            <Cell key={entry.name} fill={entry.color} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  ) : (
    <p className="grid min-h-[210px] place-items-center text-center text-sm font-semibold text-muted-foreground">
      {EMPTY_STATE_TEXT.noDestinations}
    </p>
  )}
</ChartPanel>
```

- [ ] **Step 5: Run tests**

Run:

```bash
npm test -- TodaySummary.test.tsx ChartTooltip.test.tsx ChartLegend.test.tsx
```

Expected: tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add src/components/dashboard/TodaySummary.tsx src/components/dashboard/TodaySummary.test.tsx
git commit -m "feat: polish today summary charts"
```

Expected: commit contains only TodaySummary chart changes and tests.

---

### Task 7: Polish `WeeklyTrends` Chart

**Files:**
- Modify: `src/components/dashboard/WeeklyTrends.tsx`
- Modify: `src/components/dashboard/WeeklyTrends.test.tsx`

- [ ] **Step 1: Add failing tests**

Update the Recharts mock in `WeeklyTrends.test.tsx`:

```tsx
  ReferenceLine: ({ label, y }: { label?: string; y?: number }) => <span>{`${label}:${y}`}</span>,
  Tooltip: ({ content }: { content?: ReactNode }) => <div>{content}</div>,
```

Add:

```tsx
it("renders a productivity reference line and shared legend", () => {
  render(
    <WeeklyTrends
      sessions={[session({ category: "productive", durationSeconds: 600 })]}
      summary={{ ...emptySummary, productiveSeconds: 600, trackedSeconds: 600 }}
    />,
  );

  expect(screen.getByText("목표:50")).toBeInTheDocument();
  expect(screen.getByLabelText("차트 범례")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- WeeklyTrends.test.tsx
```

Expected: test fails because the reference line and shared legend are not implemented.

- [ ] **Step 3: Import chart helpers and Recharts reference line**

Modify imports in `WeeklyTrends.tsx`:

```tsx
import {
  Bar,
  CartesianGrid,
  ComposedChart,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ChartLegend } from "../charts/ChartLegend";
import { ChartPanel } from "../charts/ChartPanel";
import { ChartTooltip } from "../charts/ChartTooltip";
```

Remove `Legend` from the Recharts import.

- [ ] **Step 4: Add legend data**

Inside `WeeklyTrends`, add:

```tsx
const legendItems = [
  { label: CATEGORY_LABELS.productive, color: CATEGORY_COLORS.productive },
  { label: CATEGORY_LABELS.unproductive, color: CATEGORY_COLORS.unproductive },
  { label: CATEGORY_LABELS.neutral, color: CATEGORY_COLORS.neutral },
  { label: CATEGORY_LABELS.ignored, color: CATEGORY_COLORS.ignored },
  { label: CATEGORY_LABELS.uncategorized, color: CATEGORY_COLORS.uncategorized },
  { label: "유휴", color: IDLE_COLOR },
  { label: "생산성 비율", color: "#111827" },
];
```

- [ ] **Step 5: Replace chart panel and legend**

Replace the wrapper with:

```tsx
<ChartPanel
  ariaLabel="주간 분류별 사용 시간과 생산성 비율 차트"
  className="min-h-[332px] p-2"
>
  {hasTrendData ? (
    <div className="grid gap-3">
      <ResponsiveContainer width="100%" height={300}>
        <ComposedChart data={trendData} margin={{ top: 16, right: 16, bottom: 0, left: 8 }}>
          <CartesianGrid strokeDasharray="3 3" vertical={false} />
          <XAxis dataKey="label" tickLine={false} axisLine={false} />
          <YAxis yAxisId="time" tickFormatter={(value) => formatDuration(Number(value))} tickLine={false} axisLine={false} />
          <YAxis yAxisId="ratio" orientation="right" domain={[0, 100]} tickFormatter={(value) => `${value}%`} />
          <Tooltip content={<ChartTooltip />} />
          <ReferenceLine yAxisId="ratio" y={50} label="목표" stroke="#64748b" strokeDasharray="4 4" />
          <Bar yAxisId="time" dataKey="productive" name="productive" stackId="time" fill={CATEGORY_COLORS.productive} />
          <Bar yAxisId="time" dataKey="unproductive" name="unproductive" stackId="time" fill={CATEGORY_COLORS.unproductive} />
          <Bar yAxisId="time" dataKey="neutral" name="neutral" stackId="time" fill={CATEGORY_COLORS.neutral} />
          <Bar yAxisId="time" dataKey="ignored" name="ignored" stackId="time" fill={CATEGORY_COLORS.ignored} />
          <Bar yAxisId="time" dataKey="uncategorized" name="uncategorized" stackId="time" fill={CATEGORY_COLORS.uncategorized} />
          <Bar yAxisId="time" dataKey="idle" name="idle" stackId="time" fill={IDLE_COLOR} />
          <Line
            yAxisId="ratio"
            type="monotone"
            dataKey="ratio"
            name="ratio"
            stroke="#111827"
            strokeWidth={2}
            dot={{ r: 3 }}
            activeDot={{ r: 5 }}
          />
        </ComposedChart>
      </ResponsiveContainer>
      <ChartLegend items={legendItems} />
    </div>
  ) : (
    <p className="grid min-h-[280px] place-items-center text-center text-sm font-semibold text-muted-foreground">
      {EMPTY_STATE_TEXT.noWeeklyActivity}
    </p>
  )}
</ChartPanel>
```

- [ ] **Step 6: Run tests**

Run:

```bash
npm test -- WeeklyTrends.test.tsx ChartTooltip.test.tsx ChartLegend.test.tsx
```

Expected: tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add src/components/dashboard/WeeklyTrends.tsx src/components/dashboard/WeeklyTrends.test.tsx
git commit -m "feat: polish weekly trend chart"
```

Expected: commit contains only WeeklyTrends chart changes and tests.

---

### Task 8: Full Verification, Visual QA, and macOS Package

**Files:**
- No source files should be changed unless verification finds a defect.

- [ ] **Step 1: Run full frontend tests**

Run:

```bash
npm test
```

Expected: all frontend tests pass.

- [ ] **Step 2: Run browser extension tests**

Run:

```bash
npm test --prefix browser-extension
```

Expected: browser extension tests pass.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
source "$HOME/.cargo/env" && cargo test --manifest-path src-tauri/Cargo.toml
```

Expected: Rust tests pass.

- [ ] **Step 4: Run production build**

Run:

```bash
npm run build
```

Expected: TypeScript and Vite build pass. Existing Vite chunk-size warning is acceptable.

- [ ] **Step 5: Run local app for visual QA**

Run:

```bash
npm run dev -- --host 127.0.0.1
```

Expected: Vite serves the app at `http://127.0.0.1:5173/`.

Capture desktop `1280x900` and narrow `390x844` screenshots for:

- Today Summary
- Timeline
- Weekly Report
- Uncategorized Review
- Rules

Check:

- No page-level horizontal overflow.
- Usage and rules table search controls fit.
- Sort buttons are reachable and labels do not clip.
- Chart legends wrap cleanly.
- Chart labels and axes do not overlap on narrow width.

- [ ] **Step 6: Fix visual defects with TDD**

If visual QA finds a defect, write a focused failing test first. Example for overflow:

```tsx
it("keeps usage rows responsive in narrow layouts", () => {
  render(<UsageTable sessions={[session({ domain: "very-long-domain-name.example.com" })]} />);
  expect(screen.getByRole("row", { name: /very-long-domain-name/ })).toHaveClass("max-[640px]:block");
});
```

Run the failing test, implement the smallest fix, then rerun the test.

- [ ] **Step 7: Package macOS app**

Run:

```bash
npm run package:macos
```

Expected:

- `src-tauri/target/release/bundle/macos/FlowPilot.app`
- `src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg`

- [ ] **Step 8: Verify macOS artifacts**

Run:

```bash
codesign --verify --deep --strict --verbose=2 src-tauri/target/release/bundle/macos/FlowPilot.app
hdiutil verify src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg
```

Expected:

- `FlowPilot.app: valid on disk`
- DMG checksum is `VALID`

- [ ] **Step 9: Final fix commit when visual QA changed files**

If visual QA required follow-up fixes, commit the affected implementation and test files from this known set:

```bash
git add src/components/tables/UsageTable.tsx src/components/tables/UsageTable.test.tsx src/components/rules/RulesSettings.tsx src/components/rules/RulesSettings.test.tsx src/components/dashboard/TodaySummary.tsx src/components/dashboard/TodaySummary.test.tsx src/components/dashboard/WeeklyTrends.tsx src/components/dashboard/WeeklyTrends.test.tsx src/components/charts/ChartPanel.tsx src/components/charts/ChartTooltip.tsx src/components/charts/ChartLegend.tsx
git commit -m "fix: polish advanced analytics responsive layout"
```

If no fixes were needed, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Recharts remains the chart engine: Tasks 5, 6, 7.
- TanStack Table is added headlessly: Tasks 1, 3, 4.
- UsageTable sorting/filtering/responsive rows: Task 3.
- Rules table sorting/filtering while preserving behavior: Task 4.
- Review queue remains unchanged except existing responsive fix: current worktree note and out-of-scope handling.
- Chart tooltip/legend/panel helpers: Task 5.
- Today Summary chart polish: Task 6.
- Weekly Trends reference line and legend polish: Task 7.
- Full tests, visual QA, package: Task 8.

Placeholder scan:

- No `TBD`, `TODO`, or incomplete implementation steps remain.

Type consistency:

- `UsageRow`, `ClassificationRule`, `SortingState`, `ChartTooltip`, `ChartLegend`, and `ChartPanel` names are introduced before use.
- Table helper paths match the file structure.
- Commands use existing npm and cargo scripts.
