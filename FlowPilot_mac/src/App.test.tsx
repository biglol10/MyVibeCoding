import { act } from "react";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  createRule,
  getPlatformPermissionStatus,
  getTodaySessions,
  getTodaySummary,
  listRules,
} from "./api/activityApi";
import App from "./App";
import type {
  ActivitySession,
  ClassificationRule,
  TodaySummary as TodaySummaryDto,
} from "./types/activity";

vi.mock("./api/activityApi", () => ({
  createRule: vi.fn(),
  getPlatformPermissionStatus: vi.fn(),
  getTodaySessions: vi.fn(),
  getTodaySummary: vi.fn(),
  listRules: vi.fn(),
}));

const todaySummary: TodaySummaryDto = {
  trackedSeconds: 5400,
  productiveSeconds: 2700,
  unproductiveSeconds: 1800,
  neutralSeconds: 0,
  idleSeconds: 0,
  uncategorizedSeconds: 900,
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
    category: "uncategorized",
    matchedRuleId: null,
    ...overrides,
  };
}

const todaySessions: ActivitySession[] = [
  session({
    id: "chatgpt",
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "ChatGPT",
    domain: "chatgpt.com",
    category: "productive",
    matchedRuleId: "builtin:domain:chatgpt.com",
    durationSeconds: 2700,
  }),
  session({
    id: "youtube",
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "YouTube",
    domain: "youtube.com",
    category: "unproductive",
    matchedRuleId: "builtin:domain:youtube.com",
    durationSeconds: 1800,
  }),
  session({
    id: "code",
    appName: "Code",
    processName: "Code.exe",
    windowTitle: "Untitled workspace",
    domain: null,
    category: "uncategorized",
    durationSeconds: 900,
  }),
];

const existingRule: ClassificationRule = {
  id: "builtin:domain:chatgpt.com",
  name: "ChatGPT",
  ruleType: "domain",
  pattern: "chatgpt.com",
  category: "productive",
  priority: 0,
  isBuiltin: true,
  isEnabled: true,
};

const codeRule: ClassificationRule = {
  id: "user:app:Code.exe",
  name: "Code",
  ruleType: "app",
  pattern: "Code.exe",
  category: "productive",
  priority: 100,
  isBuiltin: false,
  isEnabled: true,
};

describe("App", () => {
  beforeEach(() => {
    vi.mocked(getPlatformPermissionStatus).mockResolvedValue({
      platform: "other",
      accessibilityGranted: true,
      screenRecordingGranted: true,
      accessibilityRequiredReason: "",
      screenRecordingRequiredReason: "",
      canPromptAccessibility: false,
      canPromptScreenRecording: false,
    });
    vi.mocked(getTodaySummary).mockResolvedValue(todaySummary);
    vi.mocked(getTodaySessions).mockResolvedValue(todaySessions);
    vi.mocked(listRules).mockResolvedValue([existingRule]);
    vi.mocked(createRule).mockResolvedValue(codeRule);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it("renders dashboard sections from activity data", async () => {
    const user = userEvent.setup();
    render(<App />);

    expect(screen.getByRole("heading", { name: "FlowPilot" })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: "오늘 요약" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "핵심 지표" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "상위 사용 항목" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "규칙 관리" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "타임라인" }));
    expect(screen.getByRole("heading", { name: "타임라인" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "오늘 타임라인" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "핵심 지표" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "분류 규칙" }));
    expect(await screen.findByRole("heading", { name: "분류 규칙" })).toBeInTheDocument();
  });

  it("reloads the rules table after a quick rule is created", async () => {
    const user = userEvent.setup();
    vi.mocked(listRules)
      .mockResolvedValueOnce([existingRule])
      .mockResolvedValueOnce([codeRule, existingRule]);
    render(<App />);

    await screen.findByRole("heading", { name: "오늘 요약" });
    await user.click(screen.getByRole("button", { name: "분류 규칙" }));
    expect(await screen.findByText("ChatGPT")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "미분류 검토 1" }));
    const reviewRow = screen.getByRole("row", { name: /code/i });
    await user.click(within(reviewRow).getByRole("button", { name: "생산적" }));

    await user.click(screen.getByRole("button", { name: "분류 규칙" }));
    await waitFor(() => expect(listRules).toHaveBeenCalledTimes(2));
    expect(
      screen.getByRole("row", { name: /Code 앱 Code\.exe 생산적 100 사용자 규칙/i }),
    ).toBeInTheDocument();
  });

  it("refreshes dashboard data every minute", async () => {
    vi.useFakeTimers();
    vi.mocked(getTodaySummary)
      .mockResolvedValueOnce(todaySummary)
      .mockResolvedValueOnce({
        ...todaySummary,
        productiveSeconds: 3300,
        trackedSeconds: 6000,
      });
    vi.mocked(getTodaySessions)
      .mockResolvedValueOnce(todaySessions)
      .mockResolvedValueOnce([
        ...todaySessions,
        session({
          id: "notion",
          appName: "Notion",
          processName: "Notion",
          windowTitle: "Product spec",
          category: "productive",
          matchedRuleId: "user:app:Notion",
          durationSeconds: 600,
        }),
      ]);

    render(<App />);
    await act(async () => {});

    expect(getTodaySummary).toHaveBeenCalledTimes(1);
    expect(getTodaySessions).toHaveBeenCalledTimes(1);
    expect(screen.getAllByText("3개 세션").length).toBeGreaterThan(0);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(59_000);
    });
    expect(getTodaySummary).toHaveBeenCalledTimes(1);
    expect(getTodaySessions).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1_000);
    });
    expect(getTodaySummary).toHaveBeenCalledTimes(2);
    expect(getTodaySessions).toHaveBeenCalledTimes(2);
    expect(screen.getAllByText("4개 세션").length).toBeGreaterThan(0);
  });
});
