import { render, screen } from "@testing-library/react";
import { TodayPage } from "./TodayPage";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../types/activity";

vi.mock("../components/dashboard/TodaySummary", () => ({
  TodaySummary: ({ sessions }: { sessions: ActivitySession[] }) => (
    <div data-testid="today-summary">{sessions.map((session) => session.id).join(",")}</div>
  ),
}));

vi.mock("../components/dashboard/WeeklyTrends", () => ({
  WeeklyTrends: ({ compact, sessions }: { compact?: boolean; sessions: ActivitySession[] }) => (
    <div data-compact={String(compact)} data-testid="weekly-trends">
      {sessions.map((session) => session.id).join(",")}
    </div>
  ),
}));

vi.mock("../components/tables/UsageTable", () => ({
  UsageTable: ({ sessions }: { sessions: ActivitySession[] }) => (
    <div data-testid="usage-table">{sessions.map((session) => session.id).join(",")}</div>
  ),
}));

const emptySummary: TodaySummaryDto = {
  trackedSeconds: 0,
  productiveSeconds: 0,
  unproductiveSeconds: 0,
  neutralSeconds: 0,
  idleSeconds: 0,
  uncategorizedSeconds: 0,
};

function session(id: string): ActivitySession {
  return {
    id,
    startedAt: "2026-06-25T09:00:00.000Z",
    endedAt: "2026-06-25T09:10:00.000Z",
    durationSeconds: 600,
    appName: "Chrome",
    processName: "Google Chrome",
    windowTitle: id,
    domain: null,
    isIdle: false,
    category: "productive",
    matchedRuleId: null,
  };
}

describe("TodayPage", () => {
  it("keeps today-only widgets separate from the compact weekly trend", () => {
    const todaySessions = [session("today")];
    const weekSessions = [session("yesterday"), ...todaySessions];

    render(
      <TodayPage
        sessions={todaySessions}
        summary={emptySummary}
        trendSessions={weekSessions}
      />,
    );

    expect(screen.getByTestId("today-summary")).toHaveTextContent("today");
    expect(screen.getByTestId("today-summary")).not.toHaveTextContent("yesterday");
    expect(screen.getByTestId("usage-table")).toHaveTextContent("today");
    expect(screen.getByTestId("usage-table")).not.toHaveTextContent("yesterday");
    expect(screen.getByTestId("weekly-trends")).toHaveTextContent("yesterday,today");
    expect(screen.getByTestId("weekly-trends")).toHaveAttribute("data-compact", "true");
  });
});
