import { render, screen } from "@testing-library/react";
import type { HeatmapBucket, ReportActivitySession, TodaySummary } from "../types/activity";
import { WeeklyReportPage } from "./WeeklyReportPage";

vi.mock("../components/dashboard/WeeklyTrends", () => ({
  WeeklyTrends: () => <div>weekly trends</div>,
}));

vi.mock("../components/dashboard/ActivityHeatmap", () => ({
  ActivityHeatmap: ({ buckets }: { buckets: HeatmapBucket[] }) => <div>heatmap buckets: {buckets.length}</div>,
}));

vi.mock("../components/tables/UsageTable", () => ({
  UsageTable: () => <div>usage table</div>,
}));

const summary: TodaySummary = {
  idleSeconds: 0,
  neutralSeconds: 0,
  productiveSeconds: 0,
  trackedSeconds: 0,
  uncategorizedSeconds: 0,
  unproductiveSeconds: 0,
};

describe("WeeklyReportPage", () => {
  it("renders the activity heatmap with report buckets", () => {
    render(
      <WeeklyReportPage
        heatmap={[{ dominantCategory: "productive", hour: 9, seconds: 1_800, weekday: 0 }]}
        sessions={[] as ReportActivitySession[]}
        summary={summary}
      />,
    );

    expect(screen.getByText("weekly trends")).toBeInTheDocument();
    expect(screen.getByText("heatmap buckets: 1")).toBeInTheDocument();
    expect(screen.getByText("usage table")).toBeInTheDocument();
  });
});
