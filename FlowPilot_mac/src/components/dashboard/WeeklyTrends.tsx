import {
  Bar,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { CATEGORY_COLORS, IDLE_COLOR } from "../../lib/colors";
import { isMeasuredSession } from "../../lib/activityFilters";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../../types/activity";

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

interface TrendTooltipProps {
  active?: boolean;
  label?: string;
  payload?: Array<{
    color?: string;
    dataKey?: string;
    name?: string;
    value?: number;
  }>;
}

const dayFormatter = new Intl.DateTimeFormat("ko-KR", { weekday: "short" });

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
    if (!isMeasuredSession(session)) {
      continue;
    }

    const key = keyForDate(new Date(session.startedAt));
    const day = data.get(key);

    if (!day) {
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

function TrendTooltip({ active, label, payload }: TrendTooltipProps) {
  if (!active || !payload?.length) {
    return null;
  }

  return (
    <div className="min-w-44 rounded-md border bg-popover/95 px-3 py-2 text-xs shadow-xl backdrop-blur">
      <div className="mb-2 font-bold text-popover-foreground">{label}</div>
      <div className="space-y-1">
        {payload.map((entry) => {
          const isRatio = entry.dataKey === "ratio";

          return (
            <div className="flex items-center justify-between gap-4" key={entry.dataKey}>
              <span className="inline-flex items-center gap-2 text-muted-foreground">
                <i className="size-2 rounded-full" style={{ backgroundColor: entry.color ?? "#64748b" }} />
                {entry.name}
              </span>
              <strong className="tabular-nums text-popover-foreground">
                {isRatio ? `${Number(entry.value ?? 0)}%` : formatDuration(Number(entry.value ?? 0))}
              </strong>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function WeeklyTrends({ compact = false, sessions, summary }: WeeklyTrendsProps) {
  const trendData = buildTrendData(sessions, summary);
  const hasTrendData = trendData.some((day) => {
    return day.productive + day.unproductive + day.neutral + day.uncategorized + day.idle > 0;
  });

  return (
    <Card aria-labelledby="weekly-trends-title">
      <CardHeader className="border-b">
        <CardTitle id="weekly-trends-title">{compact ? "주간 흐름" : "분류별 리포트"}</CardTitle>
        <CardDescription>분류별 사용 시간과 생산성 비율</CardDescription>
      </CardHeader>

      <CardContent className="p-4">
        <div
          className="h-[336px] rounded-md border bg-[linear-gradient(180deg,var(--card),var(--secondary))] p-3 shadow-sm"
          role="img"
          aria-label="주간 분류별 사용 시간과 생산성 비율 차트"
        >
          {hasTrendData ? (
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={trendData} margin={{ top: 18, right: 18, bottom: 0, left: 8 }}>
                <CartesianGrid stroke="#dbe4f0" strokeDasharray="4 6" vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} />
                <YAxis yAxisId="time" tickFormatter={(value) => formatDuration(Number(value))} tickLine={false} axisLine={false} />
                <YAxis
                  yAxisId="ratio"
                  orientation="right"
                  domain={[0, 100]}
                  tickFormatter={(value) => `${value}%`}
                  tickLine={false}
                  axisLine={false}
                />
                <Tooltip
                  content={<TrendTooltip />}
                  cursor={{ fill: "rgba(99, 102, 241, 0.08)" }}
                  formatter={(value, name) => {
                    if (name === "ratio") {
                      return [`${Number(value)}%`, "생산성 비율"];
                    }

                    const label = name === "idle" ? "유휴" : CATEGORY_LABELS[name as keyof typeof CATEGORY_LABELS];
                    return [formatDuration(Number(value)), label ?? String(name)];
                  }}
                />
                <Legend iconType="circle" wrapperStyle={{ fontSize: 12, fontWeight: 700, paddingTop: 8 }} />
                <Bar
                  yAxisId="time"
                  dataKey="productive"
                  name={CATEGORY_LABELS.productive}
                  stackId="time"
                  fill={CATEGORY_COLORS.productive}
                  radius={[6, 6, 0, 0]}
                />
                <Bar yAxisId="time" dataKey="unproductive" name={CATEGORY_LABELS.unproductive} stackId="time" fill={CATEGORY_COLORS.unproductive} />
                <Bar yAxisId="time" dataKey="neutral" name={CATEGORY_LABELS.neutral} stackId="time" fill={CATEGORY_COLORS.neutral} />
                <Bar yAxisId="time" dataKey="uncategorized" name={CATEGORY_LABELS.uncategorized} stackId="time" fill={CATEGORY_COLORS.uncategorized} />
                <Bar yAxisId="time" dataKey="idle" name="유휴" stackId="time" fill={IDLE_COLOR} radius={[6, 6, 0, 0]} />
                <Line
                  yAxisId="ratio"
                  type="monotone"
                  dataKey="ratio"
                  name="생산성 비율"
                  stroke="#111827"
                  strokeWidth={3}
                  dot={{ fill: "#111827", r: 3 }}
                  activeDot={{ r: 6, stroke: "#ffffff", strokeWidth: 2 }}
                />
              </ComposedChart>
            </ResponsiveContainer>
          ) : (
            <p className="grid h-full place-items-center rounded-lg border border-dashed bg-muted/25 text-center text-sm font-semibold text-muted-foreground">
              {EMPTY_STATE_TEXT.noWeeklyActivity}
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
