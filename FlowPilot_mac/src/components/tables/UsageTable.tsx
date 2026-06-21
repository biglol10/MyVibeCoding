import { useMemo, type CSSProperties } from "react";
import type { ColumnDef } from "@tanstack/react-table";
import { Pencil } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { DataTable, SortableHeader } from "@/components/ui/data-table";
import { colorForCategory } from "../../lib/colors";
import { isMeasuredSession } from "../../lib/activityFilters";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT, RULE_SOURCE_LABELS } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory, ReportActivitySession } from "../../types/activity";

type DisplaySession = ActivitySession & Partial<Pick<ReportActivitySession, "displayName" | "note" | "categorySource">>;

interface UsageTableProps {
  description?: string;
  maxRows?: number;
  onEditSession?: (session: DisplaySession) => void;
  sessions: DisplaySession[];
  title?: string;
}

interface UsageRow {
  category: ProductivityCategory;
  durationSeconds: number;
  idleSeconds: number;
  isIdle: boolean;
  matchedRule: string | null;
  name: string;
  session: DisplaySession;
  share: number;
}

function displayName(session: DisplaySession): string {
  return session.displayName ?? session.domain ?? session.appName;
}

function dominantCategory(categories: Map<ProductivityCategory, number>): ProductivityCategory {
  return [...categories.entries()].sort((left, right) => right[1] - left[1])[0]?.[0] ?? "uncategorized";
}

function buildRows(sessions: ActivitySession[]): UsageRow[] {
  const measuredSessions = sessions.filter(isMeasuredSession);
  const totalSeconds = measuredSessions.reduce((total, session) => total + session.durationSeconds, 0);
  const groups = new Map<
    string,
    {
      categories: Map<ProductivityCategory, number>;
      durationSeconds: number;
      idleSeconds: number;
      matchedRules: Set<string>;
      name: string;
      session: DisplaySession;
    }
  >();

  for (const session of measuredSessions) {
    const name = displayName(session);
    const group = groups.get(name) ?? {
      categories: new Map<ProductivityCategory, number>(),
      durationSeconds: 0,
      idleSeconds: 0,
      matchedRules: new Set<string>(),
      name,
      session,
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
      session: group.session,
      share: totalSeconds > 0 ? group.durationSeconds / totalSeconds : 0,
    }))
    .sort((left, right) => right.durationSeconds - left.durationSeconds);
}

function displayRule(matchedRuleId: string | null): string {
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

function categoryBadgeStyle(color: string): CSSProperties {
  return {
    backgroundColor: `color-mix(in srgb, ${color} 10%, white)`,
    borderColor: `color-mix(in srgb, ${color} 46%, white)`,
    color,
  };
}

export function UsageTable({
  description = "앱과 사이트를 사용 시간 기준으로 정리했습니다.",
  maxRows,
  onEditSession,
  sessions,
  title = "상위 앱과 사이트",
}: UsageTableProps) {
  const rows = buildRows(sessions).slice(0, maxRows ?? Number.POSITIVE_INFINITY);
  const columns = useMemo<ColumnDef<UsageRow>[]>(
    () => [
      {
        accessorKey: "name",
        cell: ({ row }) => {
          const color = colorForCategory(row.original.category, row.original.isIdle);

          return (
            <span className="inline-flex min-w-44 max-w-64 items-center gap-2">
              <i className="size-2.5 shrink-0 rounded-full shadow-sm" style={{ backgroundColor: color }} />
              <span className="truncate font-semibold">{row.original.name}</span>
            </span>
          );
        },
        header: ({ column }) => <SortableHeader column={column}>이름</SortableHeader>,
        sortingFn: "alphanumeric",
        sortDescFirst: false,
      },
      {
        accessorKey: "category",
        cell: ({ row }) => {
          const color = colorForCategory(row.original.category, row.original.isIdle);

          return (
            <Badge
              className="h-7 min-w-20 justify-center gap-1.5 whitespace-nowrap rounded-md border px-2.5 text-[11px] font-bold leading-none shadow-none"
              style={categoryBadgeStyle(color)}
              variant="outline"
            >
              <i className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
              <span>{row.original.isIdle ? "유휴" : CATEGORY_LABELS[row.original.category]}</span>
            </Badge>
          );
        },
        header: ({ column }) => <SortableHeader column={column}>분류</SortableHeader>,
        sortingFn: (left, right) => {
          const leftLabel = left.original.isIdle ? "유휴" : CATEGORY_LABELS[left.original.category];
          const rightLabel = right.original.isIdle ? "유휴" : CATEGORY_LABELS[right.original.category];

          return leftLabel.localeCompare(rightLabel, "ko-KR");
        },
        sortDescFirst: false,
      },
      {
        accessorKey: "durationSeconds",
        cell: ({ row }) => <span className="font-semibold tabular-nums">{formatDuration(row.original.durationSeconds)}</span>,
        header: ({ column }) => <SortableHeader column={column}>시간</SortableHeader>,
        sortDescFirst: true,
      },
      {
        accessorKey: "share",
        cell: ({ row }) => {
          const color = colorForCategory(row.original.category, row.original.isIdle);
          const sharePercent = Math.round(row.original.share * 100);

          return (
            <span className="flex min-w-32 items-center gap-2" aria-label={`${sharePercent}퍼센트`}>
              <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-muted shadow-inner">
                <span
                  className="block h-full rounded-full shadow-sm"
                  style={{ width: `${sharePercent}%`, backgroundColor: color }}
                />
              </span>
              <span className="w-10 text-right text-xs font-bold tabular-nums text-muted-foreground">{sharePercent}%</span>
            </span>
          );
        },
        header: ({ column }) => <SortableHeader column={column}>비중</SortableHeader>,
        sortDescFirst: true,
      },
      {
        accessorFn: (row) => displayRule(row.matchedRule),
        cell: ({ row }) => (
          <span className="block max-w-52 truncate text-muted-foreground">{displayRule(row.original.matchedRule)}</span>
        ),
        header: ({ column }) => <SortableHeader column={column}>적용 규칙</SortableHeader>,
        id: "matchedRule",
        sortDescFirst: false,
      },
      ...(onEditSession
        ? [
            {
              cell: ({ row }) => (
                <div className="flex justify-end">
                  <Button size="sm" variant="outline" type="button" onClick={() => onEditSession(row.original.session)}>
                    <Pencil className="size-4" />
                    수정
                  </Button>
                </div>
              ),
              enableSorting: false,
              header: () => <span className="block text-right">관리</span>,
              id: "actions",
            } satisfies ColumnDef<UsageRow>,
          ]
        : []),
    ],
    [onEditSession],
  );

  return (
    <Card aria-labelledby="usage-table-title">
      <CardHeader className="border-b">
        <CardTitle id="usage-table-title">{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>

      <CardContent className="p-0">
        {rows.length > 0 ? (
          <DataTable
            columns={columns}
            data={rows}
            emptyState={EMPTY_STATE_TEXT.noDestinations}
            initialSorting={[{ desc: true, id: "durationSeconds" }]}
          />
        ) : (
          <p className="m-5 rounded-lg border border-dashed bg-muted/25 p-8 text-center text-sm font-semibold text-muted-foreground">
            {EMPTY_STATE_TEXT.noDestinations}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
