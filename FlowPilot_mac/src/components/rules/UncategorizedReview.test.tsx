import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createRule } from "../../api/activityApi";
import type { ActivitySession, ClassificationRule } from "../../types/activity";
import { UncategorizedReview } from "./UncategorizedReview";

vi.mock("../../api/activityApi", () => ({
  createRule: vi.fn(),
}));

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

const createdRule: ClassificationRule = {
  id: "user:domain:example.com",
  name: "example.com",
  ruleType: "domain",
  pattern: "example.com",
  category: "productive",
  priority: 100,
  isBuiltin: false,
  isEnabled: true,
};

describe("UncategorizedReview", () => {
  beforeEach(() => {
    vi.mocked(createRule).mockResolvedValue(createdRule);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("only shows uncategorized sessions for review", () => {
    render(
      <UncategorizedReview
        onRuleCreated={vi.fn()}
        sessions={[
          session({ id: "uncategorized", domain: "example.com" }),
          session({ id: "productive", category: "productive", domain: "chatgpt.com" }),
        ]}
      />,
    );

    expect(screen.getByText("example.com")).toBeInTheDocument();
    expect(screen.queryByText("chatgpt.com")).not.toBeInTheDocument();
  });

  it("prioritizes review targets by total uncategorized time", () => {
    render(
      <UncategorizedReview
        onRuleCreated={vi.fn()}
        sessions={[
          session({ id: "short-1", domain: "brief.example", durationSeconds: 600 }),
          session({ id: "long-1", domain: "heavy.example", durationSeconds: 1_500 }),
          session({ id: "short-2", domain: "brief.example", durationSeconds: 300 }),
        ]}
      />,
    );

    const rows = screen.getAllByRole("row");
    expect(screen.getByRole("heading", { name: "추천 규칙" })).toBeInTheDocument();
    expect(within(rows[1]).getByText("heavy.example")).toBeInTheDocument();
    expect(within(rows[2]).getByText("brief.example")).toBeInTheDocument();
  });

  it("creates a domain rule for uncategorized domains", async () => {
    const user = userEvent.setup();
    const onRuleCreated = vi.fn();
    render(
      <UncategorizedReview
        onRuleCreated={onRuleCreated}
        sessions={[session({ id: "domain", domain: "example.com" })]}
      />,
    );

    const row = screen.getByRole("row", { name: /example\.com/i });
    await user.click(within(row).getByRole("button", { name: /생산적/ }));

    expect(createRule).toHaveBeenCalledWith({
      name: "example.com",
      ruleType: "domain",
      pattern: "example.com",
      category: "productive",
    });
    expect(onRuleCreated).toHaveBeenCalledTimes(1);
  });

  it("falls back to app rules when domain is null", async () => {
    const user = userEvent.setup();
    render(
      <UncategorizedReview
        onRuleCreated={vi.fn()}
        sessions={[session({ id: "app", appName: "Code", processName: "Code.exe", domain: null })]}
      />,
    );

    const row = screen.getByRole("row", { name: /code/i });
    await user.click(within(row).getByRole("button", { name: /중립/ }));

    expect(createRule).toHaveBeenCalledWith({
      name: "Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "neutral",
    });
  });

  it("collapses repeated app sessions into one target row and creates one process-name rule", async () => {
    const user = userEvent.setup();
    render(
      <UncategorizedReview
        onRuleCreated={vi.fn()}
        sessions={[
          session({
            id: "app-1",
            appName: "Code",
            processName: "Code.exe",
            domain: null,
            durationSeconds: 600,
          }),
          session({
            id: "app-2",
            appName: "Code",
            processName: "Code.exe",
            domain: null,
            durationSeconds: 120,
          }),
        ]}
      />,
    );

    const rows = screen.getAllByRole("row");
    expect(rows).toHaveLength(2);
    const row = screen.getByRole("row", { name: /code/i });
    expect(within(row).getByText("12m")).toBeInTheDocument();
    expect(within(row).getByText("2개 세션")).toBeInTheDocument();

    await user.click(within(row).getByRole("button", { name: /제외/ }));

    expect(createRule).toHaveBeenCalledTimes(1);
    expect(createRule).toHaveBeenCalledWith({
      name: "Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "ignored",
    });
  });

  it("removes an aggregated target after a quick rule is created", async () => {
    const user = userEvent.setup();
    render(
      <UncategorizedReview
        onRuleCreated={vi.fn()}
        sessions={[
          session({
            id: "app-1",
            appName: "Code",
            processName: "Code.exe",
            domain: null,
            durationSeconds: 600,
          }),
          session({
            id: "app-2",
            appName: "Code",
            processName: "Code.exe",
            domain: null,
            durationSeconds: 120,
          }),
        ]}
      />,
    );

    const row = screen.getByRole("row", { name: /code/i });
    expect(within(row).getByText("2개 세션")).toBeInTheDocument();

    await user.click(within(row).getByRole("button", { name: /생산적/ }));

    await waitFor(() => {
      expect(screen.queryByRole("row", { name: /code/i })).not.toBeInTheDocument();
    });
    expect(screen.getByText("0개 항목 검토 필요")).toBeInTheDocument();
    expect(screen.getByText("검토할 항목이 없습니다.")).toBeInTheDocument();
  });

  it("handles app targets by process name when display names differ", async () => {
    const user = userEvent.setup();
    render(
      <UncategorizedReview
        onRuleCreated={vi.fn()}
        sessions={[
          session({
            id: "app-1",
            appName: "Visual Studio Code",
            processName: "Code.exe",
            domain: null,
            durationSeconds: 600,
          }),
          session({
            id: "app-2",
            appName: "Code - Insiders",
            processName: "Code.exe",
            domain: null,
            durationSeconds: 120,
          }),
        ]}
      />,
    );

    expect(screen.getAllByRole("row")).toHaveLength(2);
    const row = screen.getByRole("row", { name: /visual studio code/i });
    expect(within(row).getByText("2개 세션")).toBeInTheDocument();
    expect(within(row).getByText("12m")).toBeInTheDocument();
    expect(screen.queryByRole("row", { name: /code - insiders/i })).not.toBeInTheDocument();

    await user.click(within(row).getByRole("button", { name: /제외/ }));

    await waitFor(() => {
      expect(screen.queryByRole("row", { name: /visual studio code/i })).not.toBeInTheDocument();
    });
    expect(screen.getByText("0개 항목 검토 필요")).toBeInTheDocument();
    expect(createRule).toHaveBeenCalledWith({
      name: "Visual Studio Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "ignored",
    });
  });
});
