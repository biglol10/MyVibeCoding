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
import { CATEGORY_COLORS, IDLE_COLOR, colorForName } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory, TodaySummary as TodaySummaryDto } from "../../types/activity";
import { ChartLegend } from "../charts/ChartLegend";
import { ChartPanel } from "../charts/ChartPanel";
import { ChartTooltip } from "../charts/ChartTooltip";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";

interface TodaySummaryProps {
  sessions: ActivitySession[];
  summary: TodaySummaryDto;
}

interface MetricCard {
  label: string;
  value: string;
  detail: string;
  color: string;
}

const CATEGORY_KEYS: Array<Exclude<ProductivityCategory, "ignored">> = [
  "productive",
  "unproductive",
  "neutral",
  "uncategorized",
];

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

function buildCategorySeconds(sessions: ActivitySession[], summary: TodaySummaryDto): Record<ProductivityCategory, number> {
  const categorySeconds = Object.fromEntries(
    [...CATEGORY_KEYS, "ignored"].map((category) => [category, 0]),
  ) as Record<ProductivityCategory, number>;

  for (const category of CATEGORY_KEYS) {
    categorySeconds[category] = durationForCategory(category, summary);
  }

  return categorySeconds;
}

function buildTopDestinations(sessions: ActivitySession[]) {
  const totals = new Map<string, { name: string; seconds: number; color: string }>();

  for (const session of sessions) {
    if (session.category === "ignored") {
      continue;
    }

    const name = session.domain ?? session.appName;
    const current = totals.get(name) ?? { name, seconds: 0, color: colorForName(name) };
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

export function TodaySummary({ sessions, summary }: TodaySummaryProps) {
  const categorySeconds = buildCategorySeconds(sessions, summary);
  const activeTotal =
    categorySeconds.productive +
    categorySeconds.unproductive +
    categorySeconds.neutral +
    categorySeconds.uncategorized;
  const trackedTotal = Math.max(summary.trackedSeconds, activeTotal + summary.idleSeconds);
  const focusRatio = percent(summary.productiveSeconds, activeTotal);
  const metrics: MetricCard[] = [
    {
      label: "총 기록 시간",
      value: formatDuration(trackedTotal),
      detail: `${sessions.length}개 세션`,
      color: "#2563eb",
    },
    {
      label: "생산적 사용",
      value: formatDuration(summary.productiveSeconds),
      detail: `활동 시간 중 ${focusRatio}`,
      color: CATEGORY_COLORS.productive,
    },
    {
      label: "비생산 사용",
      value: formatDuration(summary.unproductiveSeconds),
      detail: `활동 시간 중 ${percent(summary.unproductiveSeconds, activeTotal)}`,
      color: CATEGORY_COLORS.unproductive,
    },
    {
      label: "유휴 시간",
      value: formatDuration(summary.idleSeconds),
      detail: `기록 시간 중 ${percent(summary.idleSeconds, trackedTotal)}`,
      color: IDLE_COLOR,
    },
  ];
  const breakdown = [
    ...CATEGORY_KEYS.map((category) => ({
      name: CATEGORY_LABELS[category],
      seconds: categorySeconds[category],
      color: CATEGORY_COLORS[category],
    })),
    {
      name: "유휴",
      seconds: summary.idleSeconds,
      color: IDLE_COLOR,
    },
  ].filter((item) => item.seconds > 0);
  const topDestinations = buildTopDestinations(sessions);
  const donutGradient = buildDonutGradient(breakdown);

  return (
    <Card aria-labelledby="today-summary-title">
      <CardHeader className="flex-row items-start justify-between gap-4 border-b">
        <div>
          <CardTitle id="today-summary-title">핵심 지표</CardTitle>
          <CardDescription>활동 시간 중 {focusRatio} 생산적 사용</CardDescription>
        </div>
        <span className="shrink-0 text-xl font-bold text-foreground">{formatDuration(trackedTotal)}</span>
      </CardHeader>

      <CardContent className="grid gap-4 pt-4">
        <div className="grid grid-cols-4 gap-3 max-[1100px]:grid-cols-2 max-[640px]:grid-cols-1">
          {metrics.map((metric) => (
            <article
              className="min-w-0 rounded-lg border border-l-4 bg-muted/25 p-3"
              key={metric.label}
              style={{ borderLeftColor: metric.color }}
            >
              <span className="block text-xs font-bold text-muted-foreground">{metric.label}</span>
              <strong className="mt-1 block text-2xl font-bold leading-tight text-foreground">{metric.value}</strong>
              <small className="mt-1 block text-xs leading-snug text-muted-foreground">{metric.detail}</small>
            </article>
          ))}
        </div>

        <div className="grid grid-cols-[minmax(280px,0.9fr)_minmax(340px,1.1fr)] gap-3 max-[980px]:grid-cols-1">
        <ChartPanel
          ariaLabel="생산성 분류 도넛 차트"
          empty={breakdown.length === 0}
          emptyText={EMPTY_STATE_TEXT.noCategoryTime}
        >
          {breakdown.length > 0 ? (
            <>
              <div
                className="mx-auto my-4 grid aspect-square w-[min(190px,70%)] place-items-center rounded-full shadow-inner"
                style={{ background: donutGradient }}
              >
                <div className="grid aspect-square w-[58%] place-items-center rounded-full border bg-card text-center shadow-sm">
                  <strong className="text-xl leading-none">{focusRatio}</strong>
                  <span className="text-xs font-bold text-muted-foreground">생산적</span>
                </div>
              </div>
              <ChartLegend entries={breakdown.map((entry) => ({ color: entry.color, name: entry.name }))} />
            </>
          ) : null}
        </ChartPanel>

        <ChartPanel
          ariaLabel="상위 사용 항목 막대 차트"
          className="p-2"
          empty={topDestinations.length === 0}
          emptyText={EMPTY_STATE_TEXT.noDestinations}
        >
          {topDestinations.length > 0 ? (
            <ResponsiveContainer width="100%" height={230}>
              <BarChart data={topDestinations} margin={{ top: 12, right: 8, bottom: 0, left: -18 }}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="name" tickLine={false} axisLine={false} tickMargin={8} />
                <YAxis tickFormatter={(value) => formatDuration(Number(value))} tickLine={false} axisLine={false} />
                <Tooltip content={<ChartTooltip />} />
                <Bar dataKey="seconds" isAnimationActive={false} radius={[6, 6, 0, 0]}>
                  {topDestinations.map((entry) => (
                    <Cell key={entry.name} fill={entry.color} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          ) : null}
        </ChartPanel>
      </div>
      </CardContent>
    </Card>
  );
}
