import { Fragment, type CSSProperties } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { CATEGORY_COLORS } from "../../lib/colors";
import { CATEGORY_LABELS } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { HeatmapBucket } from "../../types/activity";

interface ActivityHeatmapProps {
  buckets: HeatmapBucket[];
}

const WEEKDAYS = [
  { full: "월요일", short: "월" },
  { full: "화요일", short: "화" },
  { full: "수요일", short: "수" },
  { full: "목요일", short: "목" },
  { full: "금요일", short: "금" },
  { full: "토요일", short: "토" },
  { full: "일요일", short: "일" },
] as const;
const HOURS = Array.from({ length: 24 }, (_, hour) => hour);
const HEATMAP_LEGEND = [
  { color: CATEGORY_COLORS.productive, label: CATEGORY_LABELS.productive },
  { color: CATEGORY_COLORS.unproductive, label: CATEGORY_LABELS.unproductive },
  { color: CATEGORY_COLORS.neutral, label: CATEGORY_LABELS.neutral },
  { color: CATEGORY_COLORS.uncategorized, label: CATEGORY_LABELS.uncategorized },
] as const;

function bucketKey(weekday: number, hour: number): string {
  return `${weekday}:${hour}`;
}

function cellStyle(bucket: HeatmapBucket | undefined, maxSeconds: number): CSSProperties {
  if (!bucket) {
    return {};
  }

  const intensity = maxSeconds > 0 ? Math.min(1, bucket.seconds / maxSeconds) : 0;
  const alpha = 0.14 + intensity * 0.76;

  return {
    backgroundColor: `color-mix(in srgb, ${CATEGORY_COLORS[bucket.dominantCategory]} ${Math.round(alpha * 100)}%, white)`,
    borderColor: `color-mix(in srgb, ${CATEGORY_COLORS[bucket.dominantCategory]} 42%, white)`,
  } as CSSProperties;
}

function cellLabel(weekday: number, hour: number, bucket: HeatmapBucket | undefined): string {
  const prefix = `${WEEKDAYS[weekday].full} ${hour}시`;

  if (!bucket) {
    return `${prefix}, 기록 없음`;
  }

  return `${prefix}, ${formatDuration(bucket.seconds)}, ${CATEGORY_LABELS[bucket.dominantCategory]}`;
}

export function ActivityHeatmap({ buckets }: ActivityHeatmapProps) {
  const maxSeconds = Math.max(0, ...buckets.map((bucket) => bucket.seconds));
  const bucketBySlot = new Map(buckets.map((bucket) => [bucketKey(bucket.weekday, bucket.hour), bucket]));

  return (
    <Card aria-labelledby="activity-heatmap-title">
      <CardHeader className="flex-row items-start justify-between gap-4 border-b">
        <div>
          <CardTitle id="activity-heatmap-title">시간대별 활동 히트맵</CardTitle>
          <CardDescription>색이 진할수록 해당 시간대 사용 시간이 많습니다.</CardDescription>
        </div>
        <div className="flex flex-wrap justify-end gap-2 text-xs font-bold text-muted-foreground" aria-label="히트맵 분류 범례">
          {HEATMAP_LEGEND.map((item) => (
            <span className="inline-flex items-center gap-1.5" key={item.label}>
              <i className="size-2.5 rounded-sm shadow-sm" style={{ backgroundColor: item.color }} />
              {item.label}
            </span>
          ))}
        </div>
      </CardHeader>

      <CardContent className="p-4">
        {buckets.length > 0 ? (
          <div className="overflow-x-auto rounded-md border bg-[linear-gradient(180deg,var(--card),var(--secondary))] p-3 shadow-sm">
            <div
              className="grid min-w-[820px] grid-cols-[48px_repeat(24,minmax(26px,1fr))] gap-1"
              role="grid"
              aria-label="요일과 시간대별 활동 히트맵"
            >
              <span aria-hidden="true" />
              {HOURS.map((hour) => (
                <span
                  key={hour}
                  className="h-6 text-center text-[11px] font-semibold text-muted-foreground"
                  aria-hidden={hour % 6 !== 0}
                >
                  {hour % 6 === 0 ? `${hour}시` : ""}
                </span>
              ))}
              {WEEKDAYS.map((weekday, weekdayIndex) => (
                <Fragment key={weekday.full}>
                  <span className="grid h-9 place-items-center rounded-md bg-background/70 text-xs font-bold text-muted-foreground">
                    {weekday.short}
                  </span>
                  {HOURS.map((hour) => {
                    const bucket = bucketBySlot.get(bucketKey(weekdayIndex, hour));

                    return (
                      <span
                        key={hour}
                        className="h-9 rounded-md border bg-background/80 shadow-[inset_0_1px_0_rgba(255,255,255,0.55)] transition-transform hover:scale-105 hover:ring-2 hover:ring-ring/25"
                        role="gridcell"
                        aria-label={cellLabel(weekdayIndex, hour, bucket)}
                        title={cellLabel(weekdayIndex, hour, bucket)}
                        style={cellStyle(bucket, maxSeconds)}
                      />
                    );
                  })}
                </Fragment>
              ))}
            </div>
          </div>
        ) : (
          <p className="rounded-lg border border-dashed bg-muted/25 p-8 text-center text-sm font-semibold text-muted-foreground">
            아직 시간대별 활동 기록이 없습니다.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
