import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import { EMPTY_STATE_TEXT } from "../../lib/labels";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../../types/activity";
import { TodaySummary } from "./TodaySummary";

vi.mock("recharts", () => ({
  Bar: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
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
  XAxis: ({ height, interval }: { height?: number; interval?: number }) => (
    <span data-height={String(height)} data-interval={String(interval)} data-testid="top-destinations-x-axis" />
  ),
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

  it("excludes ignored sessions from breakdown and top destinations", () => {
    render(
      <TodaySummary
        sessions={[
          session({ id: "productive", domain: "docs.example.com", durationSeconds: 600 }),
          session({ id: "ignored", category: "ignored", domain: "ignored.example", durationSeconds: 300 }),
        ]}
        summary={{ ...emptySummary, productiveSeconds: 600, trackedSeconds: 600 }}
      />,
    );

    expect(screen.getByText("docs.example.com")).toBeInTheDocument();
    expect(screen.queryByText("ignored.example")).not.toBeInTheDocument();
  });

  it("keeps every top destination axis label visible", () => {
    render(
      <TodaySummary
        sessions={[
          session({ id: "one", appName: "explorer.exe", domain: null, durationSeconds: 600 }),
          session({ id: "two", appName: "Code.exe", domain: null, durationSeconds: 500 }),
          session({ id: "three", appName: "TextInputHost.exe", domain: null, durationSeconds: 400 }),
          session({ id: "four", appName: "Chrome.exe", domain: null, durationSeconds: 300 }),
          session({ id: "five", appName: "SystemSettings.exe", domain: null, durationSeconds: 200 }),
        ]}
        summary={{ ...emptySummary, productiveSeconds: 2000, trackedSeconds: 2000 }}
      />,
    );

    expect(screen.getByTestId("top-destinations-x-axis")).toHaveAttribute("data-interval", "0");
    expect(screen.getByTestId("top-destinations-x-axis")).toHaveAttribute("data-height", "56");
  });

  it("shows explicit empty states for missing breakdown and destination data", () => {
    render(<TodaySummary sessions={[]} summary={emptySummary} />);

    expect(screen.getByText(EMPTY_STATE_TEXT.noCategoryTime)).toBeInTheDocument();
    expect(screen.getByText(EMPTY_STATE_TEXT.noDestinations)).toBeInTheDocument();
  });
});
