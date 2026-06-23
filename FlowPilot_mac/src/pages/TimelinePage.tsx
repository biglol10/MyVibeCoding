import { DayTimeline } from "../components/dashboard/DayTimeline";
import { UsageTable } from "../components/tables/UsageTable";
import type { ActivitySession } from "../types/activity";

interface TimelinePageProps {
  sessions: ActivitySession[];
}

export function TimelinePage({ sessions }: TimelinePageProps) {
  return (
    <div className="grid gap-4">
      <DayTimeline sessions={sessions} />
      <UsageTable description="타임라인에 포함된 활동을 사용 시간 기준으로 정리했습니다." sessions={sessions} title="타임라인 활동 목록" />
    </div>
  );
}
