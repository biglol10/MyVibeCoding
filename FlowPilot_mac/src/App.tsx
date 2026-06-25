import { useCallback, useEffect, useMemo, useState } from "react";
import { getPlatformPermissionStatus, getTodaySessions, getTodaySummary, getWeekSessions } from "./api/activityApi";
import { AppShell } from "./components/layout/AppShell";
import { MacosPermissionNotice } from "./components/platform/MacosPermissionNotice";
import { Alert, AlertDescription, AlertTitle } from "./components/ui/alert";
import { Badge } from "./components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "./components/ui/card";
import { EMPTY_STATE_TEXT, NAV_LABELS, STATUS_LABELS } from "./lib/labels";
import { ReviewPage } from "./pages/ReviewPage";
import { RulesPage } from "./pages/RulesPage";
import { TimelinePage } from "./pages/TimelinePage";
import { TodayPage } from "./pages/TodayPage";
import { WeeklyReportPage } from "./pages/WeeklyReportPage";
import type { ActivitySession, PlatformPermissionStatus, TodaySummary as TodaySummaryDto } from "./types/activity";
import type { AppPage } from "./types/navigation";
import "./styles.css";

type DashboardState =
  | { status: "loading" }
  | { status: "ready"; todaySessions: ActivitySession[]; todaySummary: TodaySummaryDto; weekSessions: ActivitySession[] }
  | { message: string; status: "error" };

const DASHBOARD_REFRESH_INTERVAL_MS = 60_000;

export default function App() {
  const [currentPage, setCurrentPage] = useState<AppPage>("today");
  const [dashboardState, setDashboardState] = useState<DashboardState>({ status: "loading" });
  const [permissionStatus, setPermissionStatus] = useState<PlatformPermissionStatus | null>(null);
  const [rulesRefreshVersion, setRulesRefreshVersion] = useState(0);

  const loadDashboard = useCallback(async (shouldApply = () => true) => {
    try {
      const [todaySummary, todaySessions, weekSessions] = await Promise.all([
        getTodaySummary(),
        getTodaySessions(),
        getWeekSessions(),
      ]);
      if (shouldApply()) {
        setDashboardState({ status: "ready", todaySessions, todaySummary, weekSessions });
      }
    } catch (error) {
      if (shouldApply()) {
        setDashboardState({
          message: error instanceof Error ? error.message : "활동 데이터를 불러오지 못했습니다.",
          status: "error",
        });
      }
    }
  }, []);

  useEffect(() => {
    let isMounted = true;
    const shouldApply = () => isMounted;

    void loadDashboard(shouldApply);

    const refreshIntervalId = window.setInterval(() => {
      void loadDashboard(shouldApply);
    }, DASHBOARD_REFRESH_INTERVAL_MS);

    return () => {
      isMounted = false;
      window.clearInterval(refreshIntervalId);
    };
  }, [loadDashboard]);

  useEffect(() => {
    let isMounted = true;

    getPlatformPermissionStatus()
      .then((status) => {
        if (isMounted) {
          setPermissionStatus(status);
        }
      })
      .catch(() => {
        if (isMounted) {
          setPermissionStatus(null);
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

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
      dashboardState.todaySessions
        .filter((session) => session.category === "uncategorized")
        .map((session) => `${session.domain ? "domain" : "app"}:${session.domain ?? session.processName}`),
    );

    return keys.size;
  }, [dashboardState]);

  const pageSessions = useMemo(() => {
    if (dashboardState.status !== "ready") {
      return [];
    }

    return currentPage === "weekly" ? dashboardState.weekSessions : dashboardState.todaySessions;
  }, [currentPage, dashboardState]);

  function handleRuleCreated() {
    setRulesRefreshVersion((version) => version + 1);
    void loadDashboard();
  }

  return (
    <AppShell
      currentPage={currentPage}
      onPageChange={setCurrentPage}
      reviewCount={reviewCount}
      status={dashboardState.status}
      statusLabel={statusLabel}
    >
      <MacosPermissionNotice permissionStatus={permissionStatus} />

      {dashboardState.status === "loading" ? (
        <Card aria-live="polite">
          <CardHeader>
            <CardTitle>활동 기록을 불러오는 중입니다</CardTitle>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">오늘 요약 화면을 준비하고 있습니다.</CardContent>
        </Card>
      ) : null}

      {dashboardState.status === "error" ? (
        <Alert aria-live="assertive" variant="destructive">
          <AlertTitle>활동 데이터를 불러오지 못했습니다</AlertTitle>
          <AlertDescription>{dashboardState.message}</AlertDescription>
        </Alert>
      ) : null}

      {dashboardState.status === "ready" ? (
        <>
          <header className="mb-4 flex items-end justify-between gap-4">
            <div>
              <p className="m-0 text-sm font-semibold text-muted-foreground">활동 분석</p>
              <h2 className="m-0 mt-1 text-2xl font-semibold leading-tight tracking-normal">{NAV_LABELS[currentPage]}</h2>
            </div>
            <Badge className="shrink-0" variant="secondary">
              {pageSessions.length > 0
                ? `${pageSessions.length}개 세션`
                : EMPTY_STATE_TEXT.noActivityToday}
            </Badge>
          </header>

          {currentPage === "today" ? (
            <TodayPage
              sessions={dashboardState.todaySessions}
              summary={dashboardState.todaySummary}
              trendSessions={dashboardState.weekSessions}
            />
          ) : null}
          {currentPage === "timeline" ? <TimelinePage sessions={dashboardState.todaySessions} /> : null}
          {currentPage === "weekly" ? (
            <WeeklyReportPage sessions={dashboardState.weekSessions} summary={dashboardState.todaySummary} />
          ) : null}
          {currentPage === "review" ? <ReviewPage onRuleCreated={handleRuleCreated} sessions={dashboardState.todaySessions} /> : null}
          {currentPage === "rules" ? <RulesPage refreshVersion={rulesRefreshVersion} /> : null}
        </>
      ) : null}
    </AppShell>
  );
}
