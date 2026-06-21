import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import { EMPTY_STATE_TEXT } from "../../lib/labels";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../../types/activity";
import { WeeklyTrends } from "./WeeklyTrends";

vi.mock("recharts", () => ({
  Bar: ({ dataKey }: { dataKey: string }) => <span>{`bar:${dataKey}`}</span>,
  CartesianGrid: () => null,
  ComposedChart: ({ children, data }: { children?: ReactNode; data?: Array<{ ignored?: number }> }) => (
    <div>
      {data?.map((entry, index) => <span key={index}>{`ignored:${entry.ignored ?? 0}`}</span>)}
      {children}
    </div>
  ),
  Legend: () => null,
  Line: ({ dataKey }: { dataKey: string }) => <span>{`line:${dataKey}`}</span>,
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
  it("excludes ignored time from weekly trend data", () => {
    render(
      <WeeklyTrends
        sessions={[
          session({ id: "productive", category: "productive", durationSeconds: 600 }),
          session({ id: "ignored", category: "ignored", durationSeconds: 600 }),
        ]}
        summary={{ ...emptySummary, productiveSeconds: 600, trackedSeconds: 600 }}
      />,
    );

    expect(screen.queryByText("ignored:600")).not.toBeInTheDocument();
    expect(screen.queryByText("bar:ignored")).not.toBeInTheDocument();
  });

  it("shows an explicit empty state when weekly trend data has no time", () => {
    render(<WeeklyTrends sessions={[]} summary={emptySummary} />);

    expect(screen.getByText(EMPTY_STATE_TEXT.noWeeklyActivity)).toBeInTheDocument();
  });
});
