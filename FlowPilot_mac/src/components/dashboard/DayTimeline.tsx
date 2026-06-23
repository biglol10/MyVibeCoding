import { colorForCategory } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession } from "../../types/activity";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";

interface DayTimelineProps {
  sessions: ActivitySession[];
}

const timeFormatter = new Intl.DateTimeFormat("ko-KR", {
  hour: "numeric",
  minute: "2-digit",
});

function getSessionName(session: ActivitySession): string {
  return session.domain ?? session.appName;
}

export function DayTimeline({ sessions }: DayTimelineProps) {
  const sortedSessions = [...sessions].sort(
    (left, right) => new Date(left.startedAt).getTime() - new Date(right.startedAt).getTime(),
  );
  const firstStart = sortedSessions[0] ? new Date(sortedSessions[0].startedAt).getTime() : 0;
  const lastEnd = sortedSessions.reduce((latest, session) => {
    return Math.max(latest, new Date(session.endedAt).getTime());
  }, firstStart);
  const windowMs = Math.max(lastEnd - firstStart, 1);

  return (
    <Card aria-labelledby="timeline-title">
      <CardHeader className="border-b">
        <div>
          <CardTitle id="timeline-title">오늘 타임라인</CardTitle>
          <CardDescription>{sortedSessions.length}개 세션 기록</CardDescription>
        </div>
      </CardHeader>

      <CardContent className="pt-4">
      {sortedSessions.length > 0 ? (
        <>
          <div
            className="relative h-[52px] overflow-hidden rounded-lg border bg-[repeating-linear-gradient(90deg,rgba(100,116,139,0.13)_0_1px,transparent_1px_12.5%),hsl(var(--muted))]"
            aria-label="오늘 활동 세션 타임라인"
            role="list"
          >
            {sortedSessions.map((session) => {
              const start = new Date(session.startedAt).getTime();
              const color = colorForCategory(session.category, session.isIdle);
              const left = ((start - firstStart) / windowMs) * 100;
              const width = Math.max((session.durationSeconds * 1000 * 100) / windowMs, 1.5);
              const categoryLabel = session.isIdle ? "유휴" : CATEGORY_LABELS[session.category];
              const label = `${getSessionName(session)}, ${categoryLabel}, ${formatDuration(session.durationSeconds)}`;

              return (
                <span
                  aria-label={label}
                  className="absolute inset-y-0 min-w-2 border-r border-white/70 shadow-[inset_0_-14px_0_rgba(0,0,0,0.08)] focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-foreground"
                  key={session.id}
                  role="listitem"
                  style={{ left: `${left}%`, width: `${width}%`, backgroundColor: color }}
                  title={label}
                >
                  <span className="sr-only">{label}</span>
                </span>
              );
            })}
          </div>
          <div className="mt-2 flex justify-between text-xs font-semibold text-muted-foreground" aria-hidden="true">
            <span>{timeFormatter.format(new Date(firstStart))}</span>
            <span>{timeFormatter.format(new Date(lastEnd))}</span>
          </div>
        </>
      ) : (
        <p className="text-sm text-muted-foreground">{EMPTY_STATE_TEXT.noActivityToday}</p>
      )}
      </CardContent>
    </Card>
  );
}
