import { colorForCategory } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession } from "../../types/activity";
import { Badge } from "../ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";

interface DayTimelineProps {
  sessions: ActivitySession[];
}

interface TimelineHourGroup {
  key: string;
  label: string;
  sessions: ActivitySession[];
}

function getSessionName(session: ActivitySession): string {
  return session.domain ?? session.appName;
}

function padTime(value: number): string {
  return value.toString().padStart(2, "0");
}

function formatClockLabel(date: Date): string {
  return `${padTime(date.getHours())}:${padTime(date.getMinutes())}`;
}

function formatHourLabel(date: Date): string {
  return `${date.getHours()}시`;
}

function groupSessionsByHour(sessions: ActivitySession[]): TimelineHourGroup[] {
  const groups = new Map<string, TimelineHourGroup>();

  for (const session of sessions) {
    const started = new Date(session.startedAt);
    const key = `${started.getFullYear()}-${started.getMonth()}-${started.getDate()}-${started.getHours()}`;
    const group = groups.get(key);

    if (group) {
      group.sessions.push(session);
      continue;
    }

    groups.set(key, {
      key,
      label: formatHourLabel(started),
      sessions: [session],
    });
  }

  return [...groups.values()];
}

export function DayTimeline({ sessions }: DayTimelineProps) {
  const sortedSessions = sessions
    .filter((session) => session.durationSeconds > 0)
    .sort((left, right) => new Date(left.startedAt).getTime() - new Date(right.startedAt).getTime());
  const groupedSessions = groupSessionsByHour(sortedSessions);

  return (
    <Card aria-labelledby="timeline-title">
      <CardHeader className="border-b">
        <div className="flex items-start justify-between gap-4">
          <div>
          <CardTitle id="timeline-title">오늘 타임라인</CardTitle>
          <CardDescription>{sortedSessions.length}개 세션 기록</CardDescription>
          </div>
          <Badge variant="secondary">{sortedSessions.length > 0 ? `${sortedSessions.length}개` : "0개"}</Badge>
        </div>
      </CardHeader>

      <CardContent className="pt-4">
        {groupedSessions.length > 0 ? (
          <div className="grid gap-4" aria-label="오늘 활동 세션 타임라인" role="list">
            {groupedSessions.map((group) => (
              <section className="grid grid-cols-[56px_minmax(0,1fr)] gap-3" key={group.key}>
                <div className="pt-2 text-xs font-bold text-muted-foreground">{group.label}</div>
                <div className="grid gap-3 border-l border-border pl-4">
                  {group.sessions.map((session) => {
                    const color = colorForCategory(session.category, session.isIdle);
                    const startedAt = new Date(session.startedAt);
                    const endedAt = new Date(session.endedAt);
                    const categoryLabel = session.isIdle ? "유휴" : CATEGORY_LABELS[session.category];
                    const label = `${getSessionName(session)}, ${categoryLabel}, ${formatDuration(session.durationSeconds)}`;
                    const windowTitleLabel =
                      session.windowTitle && session.windowTitle !== getSessionName(session)
                        ? session.windowTitle
                        : null;

                    return (
                      <article
                        aria-label={label}
                        className="rounded-xl border bg-card p-4 shadow-sm"
                        key={session.id}
                        role="listitem"
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="min-w-0">
                            <div className="flex min-w-0 items-center gap-2">
                              <span className="size-3 shrink-0 rounded-full" style={{ backgroundColor: color }} />
                              <h3 className="truncate text-sm font-semibold text-foreground">{getSessionName(session)}</h3>
                            </div>
                            <p className="mt-1 text-xs font-medium text-muted-foreground">
                              {formatClockLabel(startedAt)} - {formatClockLabel(endedAt)}
                              {windowTitleLabel ? ` · ${windowTitleLabel}` : ""}
                            </p>
                            <p className="mt-1 text-xs text-muted-foreground/80">{session.processName}</p>
                          </div>

                          <div className="flex shrink-0 flex-col items-end gap-2">
                            <span className="text-sm font-semibold text-foreground">{formatDuration(session.durationSeconds)}</span>
                            <Badge
                              className="border"
                              style={{ borderColor: color, color }}
                              variant="outline"
                            >
                              {categoryLabel}
                            </Badge>
                          </div>
                        </div>
                      </article>
                    );
                  })}
                </div>
              </section>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">{EMPTY_STATE_TEXT.noActivityToday}</p>
        )}
      </CardContent>
    </Card>
  );
}
