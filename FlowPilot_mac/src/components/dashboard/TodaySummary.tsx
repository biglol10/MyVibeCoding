import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { CATEGORY_COLORS, IDLE_COLOR, colorForName } from "../../lib/colors";
import { isMeasuredSession } from "../../lib/activityFilters";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory, ReportActivitySession, TodaySummary as TodaySummaryDto } from "../../types/activity";

type DisplaySession = ActivitySession & Partial<Pick<ReportActivitySession, "displayName">>;

interface TodaySummaryProps {
  sessions: DisplaySession[];
  summary: TodaySummaryDto;
}

interface MetricCard {
  color: string;
  detail: string;
  label: string;
  value: string;
}

interface DestinationTooltipProps {
  active?: boolean;
  payload?: Array<{
    payload: {
      color: string;
      name: string;
      seconds: number;
    };
  }>;
}

const CATEGORY_KEYS: Exclude<ProductivityCategory, "ignored">[] = [
  "productive",
  "unproductive",
  "neutral",
  "uncategorized",
];
const DESTINATION_AXIS_LABEL_MAX_LENGTH = 18;

function percent(value: number, total: number): string {
  if (total <= 0) {
    return "0%";
  }

  return `${Math.round((value / total) * 100)}%`;
}

function durationForCategory(category: Exclude<ProductivityCategory, "ignored">, summary: TodaySummaryDto): number {
  if (category === "productive") {
    return summary.productiveSeconds;
  }

  if (category === "unproductive") {
    return summary.unproductiveSeconds;
  }

  if (category === "neutral") {
    return summary.neutralSeconds;
  }

  return summary.uncategorizedSeconds;
}

function buildCategorySeconds(summary: TodaySummaryDto): Record<Exclude<ProductivityCategory, "ignored">, number> {
  const categorySeconds = Object.fromEntries(
    CATEGORY_KEYS.map((category) => [category, 0]),
  ) as Record<Exclude<ProductivityCategory, "ignored">, number>;

  for (const category of CATEGORY_KEYS) {
    categorySeconds[category] = durationForCategory(category, summary);
  }

  return categorySeconds;
}

function buildTopDestinations(sessions: DisplaySession[]) {
  const totals = new Map<string, { color: string; name: string; seconds: number }>();

  for (const session of sessions) {
    const name = session.displayName ?? session.domain ?? session.appName;
    const current = totals.get(name) ?? { color: colorForName(name), name, seconds: 0 };
    current.seconds += session.durationSeconds;
    totals.set(name, current);
  }

  return [...totals.values()].sort((left, right) => right.seconds - left.seconds).slice(0, 5);
}

function buildDonutGradient(breakdown: Array<{ color: string; seconds: number }>): string {
  const total = breakdown.reduce((sum, item) => sum + item.seconds, 0);

  if (total <= 0) {
    return "#e2e8f0";
  }

  let cursor = 0;
  const stops = breakdown.map((item) => {
    const start = cursor;
    cursor += (item.seconds / total) * 100;
    return `${item.color} ${start}% ${cursor}%`;
  });

  return `conic-gradient(${stops.join(", ")})`;
}

function destinationAxisLabel(value: unknown): string {
  const label = String(value);

  if (label.length <= DESTINATION_AXIS_LABEL_MAX_LENGTH) {
    return label;
  }

  return `${label.slice(0, DESTINATION_AXIS_LABEL_MAX_LENGTH - 3)}...`;
}

function DestinationTooltip({ active, payload }: DestinationTooltipProps) {
  if (!active || !payload?.[0]) {
    return null;
  }

  const item = payload[0].payload;

  return (
    <div className="rounded-md border bg-popover/95 px-3 py-2 text-xs shadow-xl backdrop-blur">
      <div className="flex items-center gap-2 font-bold text-popover-foreground">
        <i className="size-2.5 rounded-full" style={{ backgroundColor: item.color }} />
        {item.name}
      </div>
      <div className="mt-1 font-semibold text-muted-foreground">{formatDuration(item.seconds)}</div>
    </div>
  );
}

export function TodaySummary({ sessions, summary }: TodaySummaryProps) {
  const measuredSessions = sessions.filter(isMeasuredSession);
  const categorySeconds = buildCategorySeconds(summary);
  const activeTotal =
    categorySeconds.productive +
    categorySeconds.unproductive +
    categorySeconds.neutral +
    categorySeconds.uncategorized;
  const trackedTotal = Math.max(summary.trackedSeconds, activeTotal + summary.idleSeconds);
  const focusRatio = percent(summary.productiveSeconds, activeTotal);
  const metrics: MetricCard[] = [
    {
      color: "#2563eb",
      detail: `${measuredSessions.length}개 세션`,
      label: "총 기록 시간",
      value: formatDuration(trackedTotal),
    },
    {
      color: CATEGORY_COLORS.productive,
      detail: `활동 시간 중 ${focusRatio}`,
      label: "생산적 사용",
      value: formatDuration(summary.productiveSeconds),
    },
    {
      color: CATEGORY_COLORS.unproductive,
      detail: `활동 시간 중 ${percent(summary.unproductiveSeconds, activeTotal)}`,
      label: "비생산적 사용",
      value: formatDuration(summary.unproductiveSeconds),
    },
    {
      color: IDLE_COLOR,
      detail: `기록 시간 중 ${percent(summary.idleSeconds, trackedTotal)}`,
      label: "유휴 시간",
      value: formatDuration(summary.idleSeconds),
    },
  ];
  const breakdown = [
    ...CATEGORY_KEYS.map((category) => ({
      color: CATEGORY_COLORS[category],
      name: CATEGORY_LABELS[category],
      seconds: categorySeconds[category],
    })),
    {
      color: IDLE_COLOR,
      name: "유휴",
      seconds: summary.idleSeconds,
    },
  ].filter((item) => item.seconds > 0);
  const topDestinations = buildTopDestinations(measuredSessions);
  const donutGradient = buildDonutGradient(breakdown);

  return (
    <Card aria-labelledby="today-summary-title">
      <CardHeader className="flex-row items-start justify-between gap-4 border-b">
        <div>
          <CardTitle id="today-summary-title">종합 지표</CardTitle>
          <CardDescription>활동 시간 중 {focusRatio} 생산적 사용</CardDescription>
        </div>
        <span className="whitespace-nowrap text-xl font-bold">{formatDuration(trackedTotal)}</span>
      </CardHeader>

      <CardContent className="space-y-4 p-4">
        <div className="grid grid-cols-4 gap-3 max-xl:grid-cols-2 max-sm:grid-cols-1">
          {metrics.map((metric) => (
            <article
              className="relative min-h-28 overflow-hidden rounded-md border bg-[linear-gradient(135deg,var(--card),var(--muted))] p-4 shadow-sm"
              key={metric.label}
            >
              <i className="absolute inset-x-0 top-0 h-1" style={{ backgroundColor: metric.color }} />
              <span className="block text-xs font-bold text-muted-foreground">{metric.label}</span>
              <strong className="mt-3 block text-2xl font-bold leading-none tabular-nums">{metric.value}</strong>
              <small className="mt-3 block text-xs font-semibold text-muted-foreground">{metric.detail}</small>
            </article>
          ))}
        </div>

        <div className="grid grid-cols-[minmax(280px,0.9fr)_minmax(340px,1.1fr)] gap-3 max-xl:grid-cols-1">
          <div className="min-h-64 rounded-md border bg-background/85 p-4 shadow-sm" role="img" aria-label="생산성 분류 도넛 차트">
            <div className="mb-2 flex items-center justify-between gap-3">
              <strong className="text-sm">분류 분포</strong>
              <span className="text-xs font-bold text-muted-foreground">{breakdown.length}개 상태</span>
            </div>
            {breakdown.length > 0 ? (
              <>
                <div
                  className="mx-auto my-4 grid aspect-square w-52 place-items-center rounded-full shadow-[inset_0_8px_22px_rgba(15,23,42,0.14)]"
                  style={{ background: donutGradient }}
                >
                  <div className="grid aspect-square w-[58%] place-items-center rounded-full border bg-card text-center shadow-lg">
                    <div>
                      <strong className="block text-2xl leading-none tabular-nums">{focusRatio}</strong>
                      <span className="mt-1 block text-xs font-bold text-muted-foreground">생산적</span>
                    </div>
                  </div>
                </div>
                <div className="flex flex-wrap gap-x-3 gap-y-2 px-1 pb-1 text-xs font-semibold text-muted-foreground">
                  {breakdown.map((entry) => (
                    <span className="inline-flex items-center gap-2" key={entry.name}>
                      <i className="block size-2.5 rounded-sm" style={{ backgroundColor: entry.color }} />
                      {entry.name}
                    </span>
                  ))}
                </div>
              </>
            ) : (
              <p className="grid min-h-52 place-items-center text-center text-sm font-semibold text-muted-foreground">
                {EMPTY_STATE_TEXT.noCategoryTime}
              </p>
            )}
          </div>

          <div className="min-h-64 rounded-md border bg-background/85 p-4 shadow-sm" role="img" aria-label="상위 사용 항목 막대 차트">
            <div className="mb-2 flex items-center justify-between gap-3">
              <strong className="text-sm">상위 사용 항목</strong>
              <span className="text-xs font-bold text-muted-foreground">TOP {topDestinations.length}</span>
            </div>
            {topDestinations.length > 0 ? (
              <ResponsiveContainer width="100%" height={230}>
                <BarChart data={topDestinations} margin={{ top: 12, right: 8, bottom: 0, left: -18 }}>
                  <defs>
                    {topDestinations.map((entry, index) => (
                      <linearGradient id={`destination-bar-${index}`} key={entry.name} x1="0" x2="0" y1="0" y2="1">
                        <stop offset="0%" stopColor={entry.color} stopOpacity={0.95} />
                        <stop offset="100%" stopColor={entry.color} stopOpacity={0.55} />
                      </linearGradient>
                    ))}
                  </defs>
                  <CartesianGrid stroke="#dbe4f0" strokeDasharray="4 6" vertical={false} />
                  <XAxis
                    axisLine={false}
                    dataKey="name"
                    height={56}
                    interval={0}
                    minTickGap={0}
                    tick={{ fontSize: 12, fontWeight: 700 }}
                    tickFormatter={destinationAxisLabel}
                    tickLine={false}
                    tickMargin={12}
                  />
                  <YAxis tickFormatter={(value) => formatDuration(Number(value))} tickLine={false} axisLine={false} />
                  <Tooltip content={<DestinationTooltip />} cursor={{ fill: "rgba(99, 102, 241, 0.08)" }} />
                  <Bar dataKey="seconds" radius={[7, 7, 3, 3]} barSize={28}>
                    {topDestinations.map((entry, index) => (
                      <Cell key={entry.name} fill={`url(#destination-bar-${index})`} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <p className="grid min-h-52 place-items-center text-center text-sm font-semibold text-muted-foreground">
                {EMPTY_STATE_TEXT.noDestinations}
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
