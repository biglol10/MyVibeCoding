import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import { WeeklyTrends } from "./WeeklyTrends";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../../types/activity";

vi.mock("recharts", () => ({
  Bar: ({
    dataKey,
    isAnimationActive,
    name,
  }: {
    dataKey: string;
    isAnimationActive?: boolean;
    name?: string;
  }) => (
    <>
      <span>{name ?? dataKey}</span>
      <span>{`bar:${dataKey}:animated:${String(isAnimationActive)}`}</span>
    </>
  ),
  CartesianGrid: () => null,
  ComposedChart: ({ children, data }: { children?: ReactNode; data?: Array<{ productive?: number }> }) => (
    <div>
      {data?.map((entry, index) => <span key={index}>{`productive:${entry.productive ?? 0}`}</span>)}
      {children}
    </div>
  ),
  Legend: () => null,
  Line: ({
    dataKey,
    isAnimationActive,
    name,
  }: {
    dataKey: string;
    isAnimationActive?: boolean;
    name?: string;
  }) => (
    <>
      <span>{name ?? dataKey}</span>
      <span>{`line:${dataKey}:animated:${String(isAnimationActive)}`}</span>
    </>
  ),
  ReferenceLine: () => null,
  ResponsiveContainer: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
  Tooltip: () => null,
  XAxis: () => null,
  YAxis: () => null,
}));

const emptySummary: TodaySummaryDto = {
  trackedSeconds: 0,
  productiveSeconds: 0,
  unproductiveSeconds: 0,
  neutralSeconds: 0,
  idleSeconds: 0,
  uncategorizedSeconds: 0,
};

function session(overrides: Partial<ActivitySession>): ActivitySession {
  return {
    id: "session",
    startedAt: new Date().toISOString(),
    endedAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    durationSeconds: 600,
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "Chrome",
    domain: "example.com",
    isIdle: false,
    category: "productive",
    matchedRuleId: null,
    ...overrides,
  };
}

describe("WeeklyTrends", () => {
  it("omits ignored time from weekly report data and legend", () => {
    render(
      <WeeklyTrends
        sessions={[
          session({ id: "productive", category: "productive", durationSeconds: 600 }),
          session({ id: "ignored", category: "ignored", durationSeconds: 600 }),
        ]}
        summary={{ ...emptySummary, productiveSeconds: 600, trackedSeconds: 600 }}
      />,
    );

    expect(screen.getByText("productive:600")).toBeInTheDocument();
    expect(screen.queryByText("제외")).not.toBeInTheDocument();
    expect(screen.queryByText("bar:ignored:animated:false")).not.toBeInTheDocument();
  });

  it("shows an explicit empty state when weekly trend data has no time", () => {
    render(<WeeklyTrends sessions={[]} summary={emptySummary} />);

    expect(screen.getByText("아직 주간 활동 기록이 없습니다.")).toBeInTheDocument();
  });

  it("disables chart animation so refreshes do not visually flicker", () => {
    render(
      <WeeklyTrends
        sessions={[session({ category: "productive", durationSeconds: 600 })]}
        summary={{ ...emptySummary, productiveSeconds: 600, trackedSeconds: 600 }}
      />,
    );

    expect(screen.getByText("bar:productive:animated:false")).toBeInTheDocument();
    expect(screen.getByText("bar:unproductive:animated:false")).toBeInTheDocument();
    expect(screen.getByText("bar:neutral:animated:false")).toBeInTheDocument();
    expect(screen.getByText("bar:uncategorized:animated:false")).toBeInTheDocument();
    expect(screen.getByText("bar:idle:animated:false")).toBeInTheDocument();
    expect(screen.getByText("line:ratio:animated:false")).toBeInTheDocument();
  });
});
