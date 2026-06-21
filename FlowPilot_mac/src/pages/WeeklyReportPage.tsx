import { ActivityHeatmap } from "../components/dashboard/ActivityHeatmap";
import { WeeklyTrends } from "../components/dashboard/WeeklyTrends";
import { UsageTable } from "../components/tables/UsageTable";
import type { HeatmapBucket, ReportActivitySession, TodaySummary as TodaySummaryDto } from "../types/activity";

interface WeeklyReportPageProps {
  heatmap?: HeatmapBucket[];
  onEditSession?: (session: ReportActivitySession) => void;
  sessions: ReportActivitySession[];
  summary: TodaySummaryDto;
}

export function WeeklyReportPage({ heatmap = [], onEditSession, sessions, summary }: WeeklyReportPageProps) {
  return (
    <div className="grid gap-4">
      <WeeklyTrends sessions={sessions} summary={summary} />
      <ActivityHeatmap buckets={heatmap} />
      <UsageTable
        description="리포트에 포함된 앱과 사이트를 사용 시간 기준으로 정렬했습니다."
        onEditSession={onEditSession}
        sessions={sessions}
        title="앱과 사이트 리포트"
      />
    </div>
  );
}
