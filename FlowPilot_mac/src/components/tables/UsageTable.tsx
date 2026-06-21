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
import { Table, TableBody, TableCell, TableHeader, TableRow } from "../ui/table";
import { AnalyticsTableToolbar } from "./AnalyticsTableToolbar";
import { SortableTableHead } from "./SortableTableHead";
import { displayCategory, displayRuleSource } from "./tableFormatting";

interface UsageTableProps {
  description?: string;
  maxRows?: number;
  sessions: ActivitySession[];
  title?: string;
}

interface UsageRow {
  category: ProductivityCategory;
  durationSeconds: number;
  idleSeconds: number;
  isIdle: boolean;
  matchedRule: string | null;
  name: string;
  share: number;
}

const columnHelper = createColumnHelper<UsageRow>();

function displayName(session: ActivitySession): string {
  return session.domain ?? session.appName;
}

function dominantCategory(categories: Map<ProductivityCategory, number>): ProductivityCategory {
  return [...categories.entries()].sort((left, right) => right[1] - left[1])[0]?.[0] ?? "uncategorized";
}

function buildRows(sessions: ActivitySession[]): UsageRow[] {
  const reportableSessions = sessions.filter((session) => session.category !== "ignored");
  const totalSeconds = reportableSessions.reduce((total, session) => total + session.durationSeconds, 0);
  const groups = new Map<
    string,
    {
      categories: Map<ProductivityCategory, number>;
      durationSeconds: number;
      idleSeconds: number;
      matchedRules: Set<string>;
      name: string;
    }
  >();

  for (const session of reportableSessions) {
    const name = displayName(session);
    const group = groups.get(name) ?? {
      categories: new Map<ProductivityCategory, number>(),
      durationSeconds: 0,
      idleSeconds: 0,
      matchedRules: new Set<string>(),
      name,
    };
    group.durationSeconds += session.durationSeconds;

    if (session.isIdle) {
      group.idleSeconds += session.durationSeconds;
    } else {
      group.categories.set(session.category, (group.categories.get(session.category) ?? 0) + session.durationSeconds);
    }

    if (session.matchedRuleId) {
      group.matchedRules.add(session.matchedRuleId);
    }

    groups.set(name, group);
  }

  return [...groups.values()]
    .map((group) => ({
      category: dominantCategory(group.categories),
      durationSeconds: group.durationSeconds,
      idleSeconds: group.idleSeconds,
      isIdle: group.durationSeconds === group.idleSeconds,
      matchedRule: [...group.matchedRules][0] ?? null,
      name: group.name,
      share: totalSeconds > 0 ? group.durationSeconds / totalSeconds : 0,
    }))
    .sort((left, right) => right.durationSeconds - left.durationSeconds);
}

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

export function UsageTable({
  description = "앱과 사이트를 사용 시간 기준으로 정리했습니다.",
  maxRows,
  sessions,
  title = "상위 앱과 사이트",
}: UsageTableProps) {
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
        cell: (info) => (
          <span className="max-w-60 [overflow-wrap:anywhere] text-muted-foreground">{info.getValue()}</span>
        ),
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

  return (
    <Card aria-labelledby="usage-table-title">
      <CardHeader className="border-b">
        <div>
          <CardTitle id="usage-table-title">{title}</CardTitle>
          <CardDescription>{description}</CardDescription>
        </div>
      </CardHeader>

      {rows.length > 0 ? (
        <CardContent className="p-0">
          <AnalyticsTableToolbar
            searchLabel="사용 항목 검색"
            searchPlaceholder="앱, 도메인, 규칙 검색"
            searchValue={globalFilter}
            onSearchChange={setGlobalFilter}
            totalRows={rows.length}
            visibleRows={visibleRows.length}
          />
          <div className="overflow-x-auto">
            <Table className="min-w-[680px] max-[640px]:min-w-0">
              <TableHeader className="max-[640px]:hidden">
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
              </TableHeader>
              <TableBody>
                {visibleRows.length > 0 ? (
                  visibleRows.map((row) => (
                    <TableRow className="max-[640px]:block max-[640px]:p-5" key={row.id}>
                      {row.getVisibleCells().map((cell) => (
                        <TableCell
                          className="max-[640px]:mt-3 max-[640px]:flex max-[640px]:items-center max-[640px]:justify-between max-[640px]:gap-4 max-[640px]:p-0"
                          key={cell.id}
                        >
                          <span
                            aria-hidden="true"
                            className="hidden shrink-0 text-xs font-semibold text-muted-foreground max-[640px]:inline"
                          >
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
                    <TableCell
                      className="h-32 text-center text-sm font-semibold text-muted-foreground"
                      colSpan={columns.length}
                    >
                      검색 결과가 없습니다.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      ) : (
        <CardContent>
          <p className="grid min-h-36 place-items-center text-center text-sm font-semibold text-muted-foreground">
            {EMPTY_STATE_TEXT.noDestinations}
          </p>
        </CardContent>
      )}
    </Card>
  );
}
