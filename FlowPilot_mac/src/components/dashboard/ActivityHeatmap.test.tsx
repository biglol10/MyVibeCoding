import { render, screen } from "@testing-library/react";
import type { HeatmapBucket } from "../../types/activity";
import { ActivityHeatmap } from "./ActivityHeatmap";

describe("ActivityHeatmap", () => {
  it("renders accessible hourly activity cells", () => {
    const buckets: HeatmapBucket[] = [
      { dominantCategory: "productive", hour: 9, seconds: 1_800, weekday: 0 },
      { dominantCategory: "unproductive", hour: 22, seconds: 3_600, weekday: 4 },
    ];

    render(<ActivityHeatmap buckets={buckets} />);

    expect(screen.getByRole("heading", { name: "시간대별 활동 히트맵" })).toBeInTheDocument();
    expect(screen.getByRole("gridcell", { name: "월요일 9시, 30m, 생산적" })).toBeInTheDocument();
    expect(screen.getByRole("gridcell", { name: "금요일 22시, 1h 0m, 비생산" })).toBeInTheDocument();
    expect(screen.getByText("0시")).toBeInTheDocument();
    expect(screen.getByText("12시")).toBeInTheDocument();
  });

  it("shows a clear empty state when there is no heatmap data", () => {
    render(<ActivityHeatmap buckets={[]} />);

    expect(screen.getByText("아직 시간대별 활동 기록이 없습니다.")).toBeInTheDocument();
  });
});
