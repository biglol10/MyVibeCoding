import { fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createRule, listRules, updateRule } from "../../api/activityApi";
import type { ClassificationRule } from "../../types/activity";
import { RulesSettings } from "./RulesSettings";

vi.mock("../../api/activityApi", () => ({
  createRule: vi.fn(),
  listRules: vi.fn(),
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
    vi.mocked(createRule).mockResolvedValue(createdRule);
    vi.mocked(updateRule).mockResolvedValue(updatedRule);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("loads rules and includes url pattern as a rule type option", async () => {
    render(<RulesSettings />);

    expect(await screen.findByText("ChatGPT")).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "URL 패턴" })).toBeInTheDocument();
  });

  it("sorts the displayed rules by name in ascending order", async () => {
    vi.mocked(listRules).mockResolvedValue([
      { ...existingRule, id: "z", name: "Zoom", pattern: "zoom.us" },
      { ...existingRule, id: "a", name: "Alpha", pattern: "alpha.example" },
      { ...existingRule, id: "n", name: "Notion", pattern: "notion.so" },
    ]);

    render(<RulesSettings />);

    const alphaRow = await screen.findByRole("row", { name: /Alpha/ });
    const rows = screen.getAllByRole("row");
    expect(rows.indexOf(alphaRow)).toBe(1);
    expect(within(rows[1]).getByText("Alpha")).toBeInTheDocument();
    expect(within(rows[2]).getByText("Notion")).toBeInTheDocument();
    expect(within(rows[3]).getByText("Zoom")).toBeInTheDocument();
  });

  it("filters rules by name or pattern and reports visible row count", async () => {
    const user = userEvent.setup();
    vi.mocked(listRules).mockResolvedValue([
      { ...existingRule, id: "chat", name: "ChatGPT", pattern: "chatgpt.com" },
      { ...existingRule, id: "video", name: "YouTube", pattern: "youtube.com" },
    ]);

    render(<RulesSettings />);
    await screen.findByText("ChatGPT");

    await user.type(screen.getByLabelText("규칙 검색"), "youtube");

    expect(screen.getByText("1 / 2개 표시")).toBeInTheDocument();
    expect(screen.getByText("YouTube")).toBeInTheDocument();
    expect(screen.queryByText("ChatGPT")).not.toBeInTheDocument();
  });

  it("uses matching column alignment classes for rule table headers and values", async () => {
    render(<RulesSettings />);

    const row = await screen.findByRole("row", { name: /ChatGPT/ });
    const headers = screen.getAllByRole("columnheader");
    const cells = within(row).getAllByRole("cell");

    expect(headers[0]).toHaveClass("w-[22%]", "text-left");
    expect(cells[0]).toHaveClass("w-[22%]", "text-left");
    expect(headers[1]).toHaveClass("w-[10%]", "text-left");
    expect(cells[1]).toHaveClass("w-[10%]", "text-left");
    expect(headers[2]).toHaveClass("w-[24%]", "text-left");
    expect(cells[2]).toHaveClass("w-[24%]", "text-left");
    expect(headers[4]).toHaveClass("w-[10%]", "text-right");
    expect(cells[4]).toHaveClass("w-[10%]", "text-right");
    expect(headers[6]).toHaveClass("w-[8%]", "text-right");
    expect(cells[6]).toHaveClass("w-[8%]", "text-right");
  });

  it("can sort displayed rules by priority", async () => {
    const user = userEvent.setup();
    vi.mocked(listRules).mockResolvedValue([
      { ...existingRule, id: "low", name: "Low", priority: 10 },
      { ...existingRule, id: "high", name: "High", priority: 200 },
    ]);

    render(<RulesSettings />);
    await screen.findByText("High");

    await user.click(screen.getByRole("button", { name: "우선순위 정렬" }));
    const rows = screen.getAllByRole("row");
    expect(within(rows[1]).getByText("Low")).toBeInTheDocument();
    expect(within(rows[2]).getByText("High")).toBeInTheDocument();
  });

  it("creates a rule, displays it in sorted order, and clears the pattern field", async () => {
    const user = userEvent.setup();
    render(<RulesSettings />);

    await screen.findByText("ChatGPT");
    await user.selectOptions(screen.getByLabelText("규칙 종류"), "urlPattern");
    await user.selectOptions(screen.getByLabelText("분류"), "unproductive");
    await user.type(screen.getByLabelText("패턴"), "/watch");
    await user.click(screen.getByRole("button", { name: "규칙 추가" }));

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
    await user.click(screen.getByRole("button", { name: "규칙 추가" }));

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
    await user.click(within(row).getByRole("button", { name: "수정" }));

    expect(screen.getByLabelText("규칙 종류")).toHaveValue("domain");
    expect(screen.getByLabelText("패턴")).toHaveValue("chatgpt.com");
    expect(screen.getByLabelText("분류")).toHaveValue("productive");
    expect(screen.getByRole("button", { name: "규칙 저장" })).toBeInTheDocument();

    await user.clear(screen.getByLabelText("패턴"));
    await user.type(screen.getByLabelText("패턴"), "openai.com");
    await user.selectOptions(screen.getByLabelText("분류"), "neutral");
    await user.click(screen.getByRole("button", { name: "규칙 저장" }));

    expect(updateRule).toHaveBeenCalledWith("builtin:domain:chatgpt.com", {
      name: "openai.com",
      ruleType: "domain",
      pattern: "openai.com",
      category: "neutral",
    });
    expect(screen.getByRole("button", { name: "규칙 추가" })).toBeInTheDocument();
    expect(screen.getByLabelText("패턴")).toHaveValue("");
    expect(screen.getByRole("row", { name: /openai\.com/ })).toBeInTheDocument();
  });

  it("preserves the existing rule name when only the category changes", async () => {
    const user = userEvent.setup();
    vi.mocked(updateRule).mockResolvedValue({ ...existingRule, category: "neutral" });
    render(<RulesSettings />);

    const row = await screen.findByRole("row", { name: /ChatGPT/ });
    await user.click(within(row).getByRole("button", { name: "수정" }));
    await user.selectOptions(screen.getByLabelText("분류"), "neutral");
    await user.click(screen.getByRole("button", { name: "규칙 저장" }));

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
