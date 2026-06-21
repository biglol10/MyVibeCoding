import { useCallback, useEffect, useMemo, useState } from "react";
import {
  deleteSessionOverride,
  getHeatmapForRange,
  getSessionsForRange,
  getSummaryForRange,
  upsertSessionOverride,
} from "./api/activityApi";
import { Card, CardContent } from "@/components/ui/card";
import { AppShell } from "./components/layout/AppShell";
import { ReportRangePicker } from "./components/reports/ReportRangePicker";
import { SessionEditModal } from "./components/sessions/SessionEditModal";
import { EMPTY_STATE_TEXT, NAV_LABELS, STATUS_LABELS } from "./lib/labels";
import { buildRangeFromPreset } from "./lib/reportRanges";
import { ReviewPage } from "./pages/ReviewPage";
import { RulesPage } from "./pages/RulesPage";
import { TimelinePage } from "./pages/TimelinePage";
import { TodayPage } from "./pages/TodayPage";
import { WeeklyReportPage } from "./pages/WeeklyReportPage";
import type { HeatmapBucket, ReportActivitySession, ReportRange, TodaySummary as TodaySummaryDto } from "./types/activity";
import type { AppPage } from "./types/navigation";

const DASHBOARD_REFRESH_INTERVAL_MS = 60_000;

type DashboardState =
  | { status: "loading" }
  | { heatmap: HeatmapBucket[]; sessions: ReportActivitySession[]; status: "ready"; summary: TodaySummaryDto }
  | { message: string; status: "error" };

export default function App() {
  const [currentPage, setCurrentPage] = useState<AppPage>("today");
  const [dashboardState, setDashboardState] = useState<DashboardState>({ status: "loading" });
  const [editingSession, setEditingSession] = useState<ReportActivitySession | null>(null);
  const [reportRange, setReportRange] = useState<ReportRange>(() => buildRangeFromPreset("today"));
  const [rulesRefreshVersion, setRulesRefreshVersion] = useState(0);

  const loadDashboard = useCallback(async (range = reportRange, shouldApply = () => true) => {
    try {
      const [summary, sessions, heatmap] = await Promise.all([
        getSummaryForRange(range),
        getSessionsForRange(range),
        getHeatmapForRange(range),
      ]);
      if (shouldApply()) {
        setDashboardState({ heatmap, sessions, status: "ready", summary });
      }
    } catch (error) {
      if (shouldApply()) {
        setDashboardState({
          message: error instanceof Error ? error.message : "활동 데이터를 불러오지 못했습니다.",
          status: "error",
        });
      }
    }
  }, [reportRange]);

  useEffect(() => {
    let isMounted = true;
    let isRefreshing = false;

    async function refreshDashboard() {
      if (isRefreshing) {
        return;
      }

      isRefreshing = true;
      try {
        await loadDashboard(reportRange, () => isMounted);
      } finally {
        isRefreshing = false;
      }
    }

    void refreshDashboard();
    const refreshTimer = window.setInterval(() => {
      void refreshDashboard();
    }, DASHBOARD_REFRESH_INTERVAL_MS);

    return () => {
      isMounted = false;
      window.clearInterval(refreshTimer);
    };
  }, [loadDashboard, reportRange]);

  const isDesktopRuntime = "__TAURI_INTERNALS__" in window;
  const statusLabel =
    dashboardState.status === "loading"
      ? STATUS_LABELS.loading
      : dashboardState.status === "error"
        ? STATUS_LABELS.error
        : isDesktopRuntime
          ? STATUS_LABELS.readyDesktop
          : STATUS_LABELS.readyDemo;

  const reviewCount = useMemo(() => {
    if (dashboardState.status !== "ready") {
      return 0;
    }

    const keys = new Set(
      dashboardState.sessions
        .filter((session) => session.category === "uncategorized")
        .map((session) => `${session.domain ? "domain" : "app"}:${session.domain ?? session.processName}`),
    );

    return keys.size;
  }, [dashboardState]);

  function handleRuleCreated() {
    setRulesRefreshVersion((version) => version + 1);
    void loadDashboard(reportRange);
  }

  function handleRangeChange(nextRange: ReportRange) {
    setReportRange(nextRange);
    setDashboardState({ status: "loading" });
  }

  async function handleSaveSessionOverride(draft: Parameters<typeof upsertSessionOverride>[0]) {
    await upsertSessionOverride(draft);
    setEditingSession(null);
    await loadDashboard(reportRange);
  }

  async function handleResetSessionOverride(sessionId: string) {
    await deleteSessionOverride(sessionId);
    setEditingSession(null);
    await loadDashboard(reportRange);
  }

  return (
    <AppShell
      currentPage={currentPage}
      onPageChange={setCurrentPage}
      reviewCount={reviewCount}
      status={dashboardState.status}
      statusLabel={statusLabel}
    >
      {dashboardState.status === "loading" ? (
        <Card aria-live="polite">
          <CardContent className="p-6">
            <h2 className="text-base font-semibold">활동 기록을 불러오는 중입니다</h2>
            <p className="mt-2 text-sm text-muted-foreground">선택한 기간의 리포트를 준비하고 있습니다.</p>
          </CardContent>
        </Card>
      ) : null}

      {dashboardState.status === "error" ? (
        <Card className="border-destructive/40 bg-destructive/5" aria-live="assertive">
          <CardContent className="p-6">
            <h2 className="text-base font-semibold text-destructive">활동 데이터를 불러오지 못했습니다</h2>
            <p className="mt-2 text-sm text-muted-foreground">{dashboardState.message}</p>
          </CardContent>
        </Card>
      ) : null}

      {dashboardState.status === "ready" ? (
        <>
          <header className="mb-5 flex items-end justify-between gap-4 max-md:flex-col max-md:items-start">
            <div>
              <p className="text-sm font-semibold text-muted-foreground">활동 분석</p>
              <h2 className="mt-1 text-2xl font-bold tracking-normal">{NAV_LABELS[currentPage]}</h2>
            </div>
            <div className="flex min-w-0 flex-wrap items-center justify-end gap-2 max-md:w-full max-md:justify-start">
              <ReportRangePicker range={reportRange} onChange={handleRangeChange} />
              <span className="text-sm font-semibold text-muted-foreground">
                {dashboardState.sessions.length > 0
                  ? `${dashboardState.sessions.length}개 세션`
                  : EMPTY_STATE_TEXT.noActivityToday}
              </span>
            </div>
          </header>

          {currentPage === "today" ? (
            <TodayPage onEditSession={setEditingSession} sessions={dashboardState.sessions} summary={dashboardState.summary} />
          ) : null}
          {currentPage === "timeline" ? <TimelinePage onEditSession={setEditingSession} sessions={dashboardState.sessions} /> : null}
          {currentPage === "weekly" ? (
            <WeeklyReportPage
              heatmap={dashboardState.heatmap}
              onEditSession={setEditingSession}
              sessions={dashboardState.sessions}
              summary={dashboardState.summary}
            />
          ) : null}
          {currentPage === "review" ? <ReviewPage onRuleCreated={handleRuleCreated} sessions={dashboardState.sessions} /> : null}
          {currentPage === "rules" ? (
            <RulesPage onGroupsChanged={() => void loadDashboard(reportRange)} refreshVersion={rulesRefreshVersion} />
          ) : null}
        </>
      ) : null}
      {editingSession ? (
        <SessionEditModal
          session={editingSession}
          onClose={() => setEditingSession(null)}
          onReset={(sessionId) => void handleResetSessionOverride(sessionId)}
          onSave={(draft) => void handleSaveSessionOverride(draft)}
        />
      ) : null}
    </AppShell>
  );
}
