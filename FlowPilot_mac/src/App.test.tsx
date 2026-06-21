import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  createRule,
  deleteSessionOverride,
  createActivityGroup,
  createDisplayNameOverride,
  deleteActivityGroup,
  deleteDisplayNameOverride,
  getHeatmapForRange,
  getSessionsForRange,
  getSummaryForRange,
  listActivityGroups,
  listDisplayNameOverrides,
  listRules,
  updateActivityGroup,
  updateDisplayNameOverride,
  upsertSessionOverride,
} from "./api/activityApi";
import App from "./App";
import type { ActivitySession, ClassificationRule, TodaySummary as TodaySummaryDto } from "./types/activity";

vi.mock("./api/activityApi", () => ({
  createActivityGroup: vi.fn(),
  createDisplayNameOverride: vi.fn(),
  createRule: vi.fn(),
  deleteActivityGroup: vi.fn(),
  deleteDisplayNameOverride: vi.fn(),
  deleteSessionOverride: vi.fn(),
  getHeatmapForRange: vi.fn(),
  getSessionsForRange: vi.fn(),
  getSummaryForRange: vi.fn(),
  listActivityGroups: vi.fn(),
  listDisplayNameOverrides: vi.fn(),
  listRules: vi.fn(),
  updateActivityGroup: vi.fn(),
  updateDisplayNameOverride: vi.fn(),
  upsertSessionOverride: vi.fn(),
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
    vi.mocked(getSummaryForRange).mockResolvedValue(todaySummary);
    vi.mocked(getSessionsForRange).mockResolvedValue(todaySessions);
    vi.mocked(getHeatmapForRange).mockResolvedValue([]);
    vi.mocked(upsertSessionOverride).mockResolvedValue(undefined);
    vi.mocked(deleteSessionOverride).mockResolvedValue(undefined);
    vi.mocked(listActivityGroups).mockResolvedValue([]);
    vi.mocked(listDisplayNameOverrides).mockResolvedValue([]);
    vi.mocked(createActivityGroup).mockResolvedValue({
      color: "#2563eb",
      id: "group:test",
      matchers: [{ id: "matcher:test", pattern: "test.com", ruleType: "domain" }],
      name: "Test",
    });
    vi.mocked(updateActivityGroup).mockResolvedValue({
      color: "#2563eb",
      id: "group:test",
      matchers: [{ id: "matcher:test", pattern: "test.com", ruleType: "domain" }],
      name: "Test",
    });
    vi.mocked(deleteActivityGroup).mockResolvedValue(undefined);
    vi.mocked(createDisplayNameOverride).mockResolvedValue({
      displayName: "Test",
      id: "display-name:app:test.exe",
      pattern: "test.exe",
      ruleType: "app",
    });
    vi.mocked(updateDisplayNameOverride).mockResolvedValue({
      displayName: "Test",
      id: "display-name:app:test.exe",
      pattern: "test.exe",
      ruleType: "app",
    });
    vi.mocked(deleteDisplayNameOverride).mockResolvedValue(undefined);
    vi.mocked(listRules).mockResolvedValue([existingRule]);
    vi.mocked(createRule).mockResolvedValue(codeRule);
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it("refreshes dashboard data once per minute while the app is open", async () => {
    vi.useFakeTimers();
    const refreshedSessions = [...todaySessions, session({ id: "notion", appName: "Notion", processName: "Notion.exe" })];
    vi.mocked(getSummaryForRange)
      .mockResolvedValueOnce(todaySummary)
      .mockResolvedValueOnce({ ...todaySummary, trackedSeconds: todaySummary.trackedSeconds + 600 });
    vi.mocked(getSessionsForRange).mockResolvedValueOnce(todaySessions).mockResolvedValueOnce(refreshedSessions);

    render(<App />);

    await act(async () => {
      await Promise.resolve();
    });
    expect(getSessionsForRange).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(59_999);
      await Promise.resolve();
    });
    expect(getSummaryForRange).toHaveBeenCalledTimes(1);
    expect(getSessionsForRange).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
      await Promise.resolve();
    });
    expect(getSummaryForRange).toHaveBeenCalledTimes(2);
    expect(getSessionsForRange).toHaveBeenCalledTimes(2);
  });

  it("reloads report data when the range preset changes", async () => {
    const user = userEvent.setup();
    render(<App />);

    await screen.findByRole("heading", { name: "오늘 요약" });
    await user.click(screen.getByRole("button", { name: "어제" }));

    await waitFor(() => expect(getSummaryForRange).toHaveBeenCalledTimes(2));
    expect(getSessionsForRange).toHaveBeenCalledTimes(2);
  });

  it("renders dashboard sections from activity data", async () => {
    const user = userEvent.setup();
    render(<App />);

    expect(screen.getByRole("heading", { name: "FlowPilot" })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: "오늘 요약" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "종합 지표" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "상위 사용 항목" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "규칙 관리" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "타임라인" }));
    expect(screen.getByRole("heading", { name: "타임라인" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "오늘 타임라인" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "종합 지표" })).not.toBeInTheDocument();

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

    await user.click(screen.getByRole("button", { name: "검토함 1" }));
    const reviewRow = screen.getByRole("row", { name: /code/i });
    await user.click(within(reviewRow).getByRole("button", { name: /생산적/ }));

    await user.click(screen.getByRole("button", { name: "분류 규칙" }));
    await waitFor(() => expect(listRules).toHaveBeenCalledTimes(2));
    expect(screen.getByRole("row", { name: /Code 앱 Code\.exe 생산적 100 사용자 규칙/i })).toBeInTheDocument();
  });
});
