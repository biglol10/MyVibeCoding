import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { colorForCategory } from "../../lib/colors";
import { isMeasuredSession } from "../../lib/activityFilters";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ReportActivitySession } from "../../types/activity";

type DisplaySession = ActivitySession & Partial<Pick<ReportActivitySession, "displayName" | "note" | "categorySource">>;

interface DayTimelineProps {
  onEditSession?: (session: DisplaySession) => void;
  sessions: DisplaySession[];
}

const timeFormatter = new Intl.DateTimeFormat("ko-KR", {
  hour: "numeric",
  minute: "2-digit",
});

function getSessionName(session: DisplaySession): string {
  return session.displayName ?? session.domain ?? session.appName;
}

export function DayTimeline({ onEditSession, sessions }: DayTimelineProps) {
  const sortedSessions = sessions.filter(isMeasuredSession).sort(
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
        <CardTitle id="timeline-title">오늘 타임라인</CardTitle>
        <CardDescription>{sortedSessions.length}개 세션 기록</CardDescription>
      </CardHeader>

      <CardContent className="p-5">
        {sortedSessions.length > 0 ? (
          <>
            <div
              className="relative h-14 overflow-hidden rounded-lg border bg-muted"
              aria-label="오늘 활동 세션 타임라인"
              role="list"
            >
              <div className="pointer-events-none absolute inset-0 bg-[repeating-linear-gradient(90deg,rgba(100,116,139,0.16)_0_1px,transparent_1px_12.5%)]" />
              {sortedSessions.map((session) => {
                const start = new Date(session.startedAt).getTime();
                const color = colorForCategory(session.category, session.isIdle);
                const left = ((start - firstStart) / windowMs) * 100;
                const width = Math.max((session.durationSeconds * 1000 * 100) / windowMs, 1.5);
                const categoryLabel = session.isIdle ? "유휴" : CATEGORY_LABELS[session.category];
                const label = `${getSessionName(session)}, ${categoryLabel}, ${formatDuration(session.durationSeconds)}`;

                return (
                  <button
                    aria-label={label}
                    className="absolute inset-y-0 min-w-2 border-0 border-r border-white/70 shadow-[inset_0_-14px_0_rgba(0,0,0,0.10)] outline-none transition-opacity hover:opacity-90 focus-visible:ring-2 focus-visible:ring-ring"
                    key={session.id}
                    onClick={onEditSession ? () => onEditSession(session) : undefined}
                    role="listitem"
                    style={{ backgroundColor: color, left: `${left}%`, width: `${width}%` }}
                    title={label}
                    type="button"
                  >
                    <span className="sr-only">{label}</span>
                  </button>
                );
              })}
            </div>
            <div className="mt-3 flex justify-between text-xs font-semibold text-muted-foreground" aria-hidden="true">
              <span>{timeFormatter.format(new Date(firstStart))}</span>
              <span>{timeFormatter.format(new Date(lastEnd))}</span>
            </div>
          </>
        ) : (
          <p className="py-8 text-center text-sm font-semibold text-muted-foreground">{EMPTY_STATE_TEXT.noActivityToday}</p>
        )}
      </CardContent>
    </Card>
  );
}
