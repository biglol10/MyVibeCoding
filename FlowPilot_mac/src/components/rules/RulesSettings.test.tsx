import { fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  createActivityGroup,
  createDisplayNameOverride,
  deleteActivityGroup,
  deleteDisplayNameOverride,
  listActivityGroups,
  listDisplayNameOverrides,
  createRule,
  listRules,
  updateDisplayNameOverride,
  updateRule,
} from "../../api/activityApi";
import type { ClassificationRule } from "../../types/activity";
import { RulesSettings } from "./RulesSettings";

vi.mock("../../api/activityApi", () => ({
  createActivityGroup: vi.fn(),
  createDisplayNameOverride: vi.fn(),
  createRule: vi.fn(),
  deleteActivityGroup: vi.fn(),
  deleteDisplayNameOverride: vi.fn(),
  listActivityGroups: vi.fn(),
  listDisplayNameOverrides: vi.fn(),
  listRules: vi.fn(),
  updateDisplayNameOverride: vi.fn(),
  updateRule: vi.fn(),
}));

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

const createdRule: ClassificationRule = {
  id: "user:urlPattern:/watch",
  name: "/watch",
  ruleType: "urlPattern",
  pattern: "/watch",
  category: "unproductive",
  priority: 100,
  isBuiltin: false,
  isEnabled: true,
};

const updatedRule: ClassificationRule = {
  ...existingRule,
  name: "openai.com",
  pattern: "openai.com",
  category: "neutral",
};

describe("RulesSettings", () => {
  beforeEach(() => {
    vi.mocked(listRules).mockResolvedValue([existingRule]);
    vi.mocked(listActivityGroups).mockResolvedValue([]);
    vi.mocked(listDisplayNameOverrides).mockResolvedValue([]);
    vi.mocked(createRule).mockResolvedValue(createdRule);
    vi.mocked(createDisplayNameOverride).mockResolvedValue({
      displayName: "Test",
      id: "display-name:app:test.exe",
      pattern: "test.exe",
      ruleType: "app",
    });
    vi.mocked(createActivityGroup).mockResolvedValue({
      id: "group:test",
      name: "Test",
      color: "#2563eb",
      matchers: [{ id: "matcher:test", ruleType: "domain", pattern: "test.com" }],
    });
    vi.mocked(deleteActivityGroup).mockResolvedValue(undefined);
    vi.mocked(deleteDisplayNameOverride).mockResolvedValue(undefined);
    vi.mocked(updateDisplayNameOverride).mockResolvedValue({
      displayName: "Test",
      id: "display-name:app:test.exe",
      pattern: "test.exe",
      ruleType: "app",
    });
    vi.mocked(updateRule).mockResolvedValue(updatedRule);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("loads rules and includes url pattern as a rule type option", async () => {
    render(<RulesSettings />);

    expect(await screen.findByText("ChatGPT")).toBeInTheDocument();
    expect(screen.getAllByRole("option", { name: "URL 패턴" }).length).toBeGreaterThan(0);
  });

  it("sorts rule rows by name ascending", async () => {
    vi.mocked(listRules).mockResolvedValue([
      { ...existingRule, id: "builtin:domain:zeta.com", name: "Zeta", pattern: "zeta.com" },
      { ...existingRule, id: "builtin:domain:alpha.com", name: "Alpha", pattern: "alpha.com" },
    ]);

    render(<RulesSettings />);

    expect(await screen.findByText("Alpha")).toBeInTheDocument();
    const rows = screen.getAllByRole("row");
    expect(within(rows[1]).getByText("Alpha")).toBeInTheDocument();
    expect(within(rows[2]).getByText("Zeta")).toBeInTheDocument();
  });

  it("creates a rule, prepends it, and clears the pattern field", async () => {
    const user = userEvent.setup();
    render(<RulesSettings />);

    await screen.findByText("ChatGPT");
    await user.selectOptions(screen.getByLabelText("규칙 종류"), "urlPattern");
    await user.selectOptions(screen.getByLabelText("분류"), "unproductive");
    await user.type(screen.getByLabelText("패턴"), "/watch");
    await user.click(screen.getByRole("button", { name: /규칙 추가/ }));

    expect(createRule).toHaveBeenCalledWith({
      name: "/watch",
      ruleType: "urlPattern",
      pattern: "/watch",
      category: "unproductive",
    });

    const rows = screen.getAllByRole("row");
    expect(within(rows[1]).getAllByText("/watch")).toHaveLength(2);
    expect(within(rows[2]).getByText("ChatGPT")).toBeInTheDocument();
    expect(screen.getByLabelText("패턴")).toHaveValue("");
  });

  it("replaces an existing rule with the returned rule instead of duplicating deterministic ids", async () => {
    const user = userEvent.setup();
    const existingDuplicate: ClassificationRule = {
      ...createdRule,
      category: "neutral",
    };
    vi.mocked(listRules).mockResolvedValue([existingDuplicate, existingRule]);
    render(<RulesSettings />);

    await screen.findByText("ChatGPT");
    await user.selectOptions(screen.getByLabelText("규칙 종류"), "urlPattern");
    await user.selectOptions(screen.getByLabelText("분류"), "unproductive");
    await user.type(screen.getByLabelText("패턴"), "/watch");
    await user.click(screen.getByRole("button", { name: /규칙 추가/ }));

    const rows = screen.getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(within(rows[1]).getAllByText("/watch")).toHaveLength(2);
    expect(within(rows[1]).getByText("비생산")).toBeInTheDocument();
    expect(within(rows[2]).getByText("ChatGPT")).toBeInTheDocument();
  });

  it("loads an existing rule into the form and saves edits in place", async () => {
    const user = userEvent.setup();
    render(<RulesSettings />);

    const row = await screen.findByRole("row", { name: /ChatGPT/ });
    await user.click(within(row).getByRole("button", { name: /수정/ }));

    expect(screen.getByLabelText("규칙 종류")).toHaveValue("domain");
    expect(screen.getByLabelText("패턴")).toHaveValue("chatgpt.com");
    expect(screen.getByLabelText("분류")).toHaveValue("productive");
    expect(screen.getByRole("button", { name: /규칙 저장/ })).toBeInTheDocument();

    await user.clear(screen.getByLabelText("패턴"));
    await user.type(screen.getByLabelText("패턴"), "openai.com");
    await user.selectOptions(screen.getByLabelText("분류"), "neutral");
    await user.click(screen.getByRole("button", { name: /규칙 저장/ }));

    expect(updateRule).toHaveBeenCalledWith("builtin:domain:chatgpt.com", {
      name: "openai.com",
      ruleType: "domain",
      pattern: "openai.com",
      category: "neutral",
    });
    expect(screen.getByRole("button", { name: /규칙 추가/ })).toBeInTheDocument();
    expect(screen.getByLabelText("패턴")).toHaveValue("");
    expect(screen.getByRole("row", { name: /openai\.com/ })).toBeInTheDocument();
  });

  it("preserves the existing rule name when only the category changes", async () => {
    const user = userEvent.setup();
    vi.mocked(updateRule).mockResolvedValue({ ...existingRule, category: "neutral" });
    render(<RulesSettings />);

    const row = await screen.findByRole("row", { name: /ChatGPT/ });
    await user.click(within(row).getByRole("button", { name: /수정/ }));
    await user.selectOptions(screen.getByLabelText("분류"), "neutral");
    await user.click(screen.getByRole("button", { name: /규칙 저장/ }));

    expect(updateRule).toHaveBeenCalledWith("builtin:domain:chatgpt.com", {
      name: "ChatGPT",
      ruleType: "domain",
      pattern: "chatgpt.com",
      category: "neutral",
    });
    expect(screen.getByRole("row", { name: /ChatGPT.*중립/ })).toBeInTheDocument();
  });

  it("marks the pattern input as required and associates validation errors", async () => {
    render(<RulesSettings />);

    const patternInput = await screen.findByLabelText("패턴");
    expect(patternInput).toBeRequired();
    expect(patternInput).toHaveAttribute("aria-invalid", "false");

    fireEvent.submit(patternInput.closest("form") as HTMLFormElement);

    const error = await screen.findByRole("alert", { name: "" });
    expect(error).toHaveTextContent("패턴을 입력해야 합니다.");
    expect(patternInput).toHaveAttribute("aria-invalid", "true");
    expect(patternInput).toHaveAttribute("aria-describedby", error.id);
  });
});
