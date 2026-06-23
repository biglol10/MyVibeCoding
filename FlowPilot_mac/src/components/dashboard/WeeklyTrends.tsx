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
import { CATEGORY_COLORS, IDLE_COLOR } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory, TodaySummary as TodaySummaryDto } from "../../types/activity";
import { ChartLegend } from "../charts/ChartLegend";
import { ChartPanel } from "../charts/ChartPanel";
import { ChartTooltip } from "../charts/ChartTooltip";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";

interface WeeklyTrendsProps {
  compact?: boolean;
  sessions: ActivitySession[];
  summary: TodaySummaryDto;
}

interface TrendDay {
  idle: number;
  label: string;
  neutral: number;
  productive: number;
  ratio: number;
  uncategorized: number;
  unproductive: number;
}

const dayFormatter = new Intl.DateTimeFormat("ko-KR", { weekday: "short" });
const WEEKLY_CATEGORY_KEYS: Array<Exclude<ProductivityCategory, "ignored">> = [
  "productive",
  "unproductive",
  "neutral",
  "uncategorized",
];

function startOfDay(date: Date): Date {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

function addDays(date: Date, days: number): Date {
  const copy = new Date(date);
  copy.setDate(copy.getDate() + days);
  return copy;
}

function keyForDate(date: Date): string {
  return startOfDay(date).toISOString().slice(0, 10);
}

function buildTrendData(sessions: ActivitySession[], summary: TodaySummaryDto): TrendDay[] {
  const today = startOfDay(new Date());
  const days = Array.from({ length: 7 }, (_, index) => addDays(today, index - 6));
  const data = new Map<string, TrendDay>();

  for (const day of days) {
    data.set(keyForDate(day), {
      idle: 0,
      label: dayFormatter.format(day),
      neutral: 0,
      productive: 0,
      ratio: 0,
      uncategorized: 0,
      unproductive: 0,
    });
  }

  for (const session of sessions) {
    const key = keyForDate(new Date(session.startedAt));
    const day = data.get(key);

    if (!day) {
      continue;
    }

    if (session.category === "ignored") {
      continue;
    }

    if (session.isIdle) {
      day.idle += session.durationSeconds;
    } else if (session.category === "productive") {
      day.productive += session.durationSeconds;
    } else if (session.category === "unproductive") {
      day.unproductive += session.durationSeconds;
    } else if (session.category === "neutral") {
      day.neutral += session.durationSeconds;
    } else {
      day.uncategorized += session.durationSeconds;
    }
  }

  const todayKey = keyForDate(today);
  const todayData = data.get(todayKey);

  if (todayData) {
    todayData.productive = Math.max(todayData.productive, summary.productiveSeconds);
    todayData.unproductive = Math.max(todayData.unproductive, summary.unproductiveSeconds);
    todayData.neutral = Math.max(todayData.neutral, summary.neutralSeconds);
    todayData.uncategorized = Math.max(todayData.uncategorized, summary.uncategorizedSeconds);
    todayData.idle = Math.max(todayData.idle, summary.idleSeconds);
  }

  return [...data.values()].map((day) => {
    const active = day.productive + day.unproductive + day.neutral + day.uncategorized;

    return {
      ...day,
      ratio: active > 0 ? Math.round((day.productive / active) * 100) : 0,
    };
  });
}

export function WeeklyTrends({ compact = false, sessions, summary }: WeeklyTrendsProps) {
  const trendData = buildTrendData(sessions, summary);
  const hasTrendData = trendData.some((day) => {
    return day.productive + day.unproductive + day.neutral + day.uncategorized + day.idle > 0;
  });
  const legendEntries = [
    ...WEEKLY_CATEGORY_KEYS.map((category) => ({
      color: CATEGORY_COLORS[category],
      name: CATEGORY_LABELS[category],
    })),
    { color: IDLE_COLOR, name: "유휴" },
  ];

  return (
    <Card aria-labelledby="weekly-trends-title">
      <CardHeader className="border-b">
        <div>
          <CardTitle id="weekly-trends-title">{compact ? "주간 흐름" : "분류별 리포트"}</CardTitle>
          <CardDescription>분류별 사용 시간과 생산성 비율</CardDescription>
        </div>
      </CardHeader>

      <CardContent className="pt-4">
      <ChartPanel
        ariaLabel="주간 분류별 사용 시간과 생산성 비율 차트"
        className="p-2"
        empty={!hasTrendData}
        emptyText={EMPTY_STATE_TEXT.noWeeklyActivity}
        minHeightClassName="min-h-[332px]"
      >
        {hasTrendData ? (
          <>
            <ResponsiveContainer width="100%" height={270}>
              <ComposedChart data={trendData} margin={{ top: 16, right: 16, bottom: 0, left: 8 }}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} />
                <YAxis
                  yAxisId="time"
                  tickFormatter={(value) => formatDuration(Number(value))}
                  tickLine={false}
                  axisLine={false}
                />
                <YAxis yAxisId="ratio" orientation="right" domain={[0, 100]} tickFormatter={(value) => `${value}%`} />
                <Tooltip
                  content={
                    <ChartTooltip
                      valueFormatter={(value, name) =>
                        name === "생산성 비율" ? `${Number(value)}%` : formatDuration(Number(value))
                      }
                    />
                  }
                />
                <ReferenceLine yAxisId="ratio" y={50} stroke="#94a3b8" strokeDasharray="4 4" />
                <Bar
                  yAxisId="time"
                  dataKey="productive"
                  name={CATEGORY_LABELS.productive}
                  stackId="time"
                  fill={CATEGORY_COLORS.productive}
                  isAnimationActive={false}
                />
                <Bar
                  yAxisId="time"
                  dataKey="unproductive"
                  name={CATEGORY_LABELS.unproductive}
                  stackId="time"
                  fill={CATEGORY_COLORS.unproductive}
                  isAnimationActive={false}
                />
                <Bar
                  yAxisId="time"
                  dataKey="neutral"
                  name={CATEGORY_LABELS.neutral}
                  stackId="time"
                  fill={CATEGORY_COLORS.neutral}
                  isAnimationActive={false}
                />
                <Bar
                  yAxisId="time"
                  dataKey="uncategorized"
                  name={CATEGORY_LABELS.uncategorized}
                  stackId="time"
                  fill={CATEGORY_COLORS.uncategorized}
                  isAnimationActive={false}
                />
                <Bar
                  yAxisId="time"
                  dataKey="idle"
                  name="유휴"
                  stackId="time"
                  fill={IDLE_COLOR}
                  isAnimationActive={false}
                />
                <Line
                  yAxisId="ratio"
                  type="monotone"
                  dataKey="ratio"
                  name="생산성 비율"
                  stroke="#111827"
                  strokeWidth={2}
                  dot={{ r: 3 }}
                  activeDot={{ r: 5 }}
                  isAnimationActive={false}
                />
              </ComposedChart>
            </ResponsiveContainer>
            <ChartLegend entries={legendEntries} />
          </>
        ) : null}
      </ChartPanel>
      </CardContent>
    </Card>
  );
}
