import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import { TodaySummary } from "./TodaySummary";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../../types/activity";

vi.mock("recharts", () => ({
  Bar: ({
    children,
    dataKey,
    isAnimationActive,
  }: {
    children?: ReactNode;
    dataKey?: string;
    isAnimationActive?: boolean;
  }) => (
    <div>
      {dataKey ? <span>{`bar:${dataKey}:animated:${String(isAnimationActive)}`}</span> : null}
      {children}
    </div>
  ),
  BarChart: ({ children, data }: { children?: ReactNode; data?: Array<{ name: string }> }) => (
    <div>
      {data?.map((entry) => <span key={entry.name}>{entry.name}</span>)}
      {children}
    </div>
  ),
  CartesianGrid: () => null,
  Cell: () => null,
  Pie: ({ children, data }: { children?: ReactNode; data?: Array<{ name: string }> }) => (
    <div>
      {data?.map((entry) => <span key={entry.name}>{entry.name}</span>)}
      {children}
    </div>
  ),
  PieChart: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
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
    startedAt: "2026-06-18T09:00:00.000Z",
    endedAt: "2026-06-18T09:10:00.000Z",
    durationSeconds: 600,
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "Chrome",
    domain: null,
    isIdle: false,
    category: "productive",
    matchedRuleId: null,
    ...overrides,
  };
}

describe("TodaySummary", () => {
  it("groups top destinations by domain before app name", () => {
    render(
      <TodaySummary
        sessions={[
          session({ id: "chat", domain: "chatgpt.com", durationSeconds: 900 }),
          session({ id: "docs", domain: "docs.example.com", durationSeconds: 600 }),
        ]}
        summary={{ ...emptySummary, productiveSeconds: 1500, trackedSeconds: 1500 }}
      />,
    );

    expect(screen.getByText("chatgpt.com")).toBeInTheDocument();
    expect(screen.getByText("docs.example.com")).toBeInTheDocument();
    expect(screen.queryByText("Chrome")).not.toBeInTheDocument();
  });

  it("omits ignored sessions from the category breakdown and top destinations", () => {
    render(
      <TodaySummary
        sessions={[
          session({ id: "productive", domain: "chatgpt.com", durationSeconds: 600, category: "productive" }),
          session({ id: "ignored", domain: "youtube.com", durationSeconds: 300, category: "ignored" }),
        ]}
        summary={{ ...emptySummary, productiveSeconds: 600, trackedSeconds: 600 }}
      />,
    );

    expect(screen.queryByText("제외")).not.toBeInTheDocument();
    expect(screen.queryByText("youtube.com")).not.toBeInTheDocument();
    expect(screen.getByText("chatgpt.com")).toBeInTheDocument();
    expect(screen.getAllByText("100%").length).toBeGreaterThan(0);
  });

  it("shows explicit empty states for missing breakdown and destination data", () => {
    render(<TodaySummary sessions={[]} summary={emptySummary} />);

    expect(screen.getByText("아직 분류된 시간이 없습니다.")).toBeInTheDocument();
    expect(screen.getByText("아직 사용 항목이 없습니다.")).toBeInTheDocument();
  });

  it("disables bar animation so refreshes do not visually flicker", () => {
    render(
      <TodaySummary
        sessions={[session({ id: "chat", domain: "chatgpt.com", durationSeconds: 900 })]}
        summary={{ ...emptySummary, productiveSeconds: 900, trackedSeconds: 900 }}
      />,
    );

    expect(screen.getByText("bar:seconds:animated:false")).toBeInTheDocument();
  });
});
