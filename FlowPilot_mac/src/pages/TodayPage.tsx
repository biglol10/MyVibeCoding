import { TodaySummary } from "../components/dashboard/TodaySummary";
import { WeeklyTrends } from "../components/dashboard/WeeklyTrends";
import { UsageTable } from "../components/tables/UsageTable";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../types/activity";

interface TodayPageProps {
  sessions: ActivitySession[];
  summary: TodaySummaryDto;
}

export function TodayPage({ sessions, summary }: TodayPageProps) {
  return (
    <div className="grid gap-4">
      <TodaySummary sessions={sessions} summary={summary} />
      <div className="grid grid-cols-[minmax(420px,0.95fr)_minmax(460px,1.05fr)] items-start gap-4 max-[1100px]:grid-cols-1">
        <UsageTable description="가장 많이 사용한 앱과 사이트 5개" maxRows={5} sessions={sessions} title="상위 사용 항목" />
        <WeeklyTrends compact sessions={sessions} summary={summary} />
      </div>
    </div>
  );
}
