import { DayTimeline } from "../components/dashboard/DayTimeline";
import { UsageTable } from "../components/tables/UsageTable";
import type { ReportActivitySession } from "../types/activity";

interface TimelinePageProps {
  onEditSession?: (session: ReportActivitySession) => void;
  sessions: ReportActivitySession[];
}

export function TimelinePage({ onEditSession, sessions }: TimelinePageProps) {
  return (
    <div className="grid gap-4">
      <DayTimeline onEditSession={onEditSession} sessions={sessions} />
      <UsageTable
        description="타임라인에 포함된 활동을 사용 시간 기준으로 정리했습니다."
        onEditSession={onEditSession}
        sessions={sessions}
        title="타임라인 활동 목록"
      />
    </div>
  );
}
