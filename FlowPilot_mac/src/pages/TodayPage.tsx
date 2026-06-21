import { TodaySummary } from "../components/dashboard/TodaySummary";
import { WeeklyTrends } from "../components/dashboard/WeeklyTrends";
import { UsageTable } from "../components/tables/UsageTable";
import type { ReportActivitySession, TodaySummary as TodaySummaryDto } from "../types/activity";

interface TodayPageProps {
  onEditSession?: (session: ReportActivitySession) => void;
  sessions: ReportActivitySession[];
  summary: TodaySummaryDto;
}

export function TodayPage({ onEditSession, sessions, summary }: TodayPageProps) {
  return (
    <div className="grid gap-4">
      <TodaySummary sessions={sessions} summary={summary} />
      <div className="grid grid-cols-[minmax(360px,1fr)_minmax(420px,1fr)] gap-4 max-xl:grid-cols-1">
        <UsageTable
          description="가장 많이 사용한 앱과 사이트 5개"
          maxRows={5}
          onEditSession={onEditSession}
          sessions={sessions}
          title="상위 사용 항목"
        />
        <WeeklyTrends compact sessions={sessions} summary={summary} />
      </div>
    </div>
  );
}
