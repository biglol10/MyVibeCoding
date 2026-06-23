import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { UsageTable } from "./UsageTable";
import type { ActivitySession } from "../../types/activity";

function session(overrides: Partial<ActivitySession>): ActivitySession {
  return {
    id: "session",
    startedAt: "2026-06-18T09:00:00.000Z",
    endedAt: "2026-06-18T09:10:00.000Z",
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

describe("UsageTable", () => {
  it("uses non-idle seconds for the dominant category in mixed rows", () => {
    render(
      <UsageTable
        sessions={[
          session({ id: "idle", category: "unproductive", durationSeconds: 3600, isIdle: true }),
          session({ id: "active", category: "productive", durationSeconds: 60, isIdle: false }),
        ]}
      />,
    );

    const row = screen.getByRole("row", { name: /example\.com/i });

    expect(within(row).getByText("생산적")).toBeInTheDocument();
    expect(within(row).queryByText("비생산")).not.toBeInTheDocument();
  });

  it("shows idle when a destination row is entirely idle", () => {
    render(<UsageTable sessions={[session({ isIdle: true })]} />);

    expect(screen.getByText("유휴")).toBeInTheDocument();
  });

  it("shows an explicit empty state when there are no rows", () => {
    render(<UsageTable sessions={[]} />);

    expect(screen.getByText("아직 사용 항목이 없습니다.")).toBeInTheDocument();
  });

  it("omits ignored sessions from the report table and share calculation", () => {
    render(
      <UsageTable
        sessions={[
          session({ id: "productive", domain: "chatgpt.com", durationSeconds: 600, category: "productive" }),
          session({ id: "ignored", domain: "youtube.com", durationSeconds: 600, category: "ignored" }),
        ]}
      />,
    );

    expect(screen.getByText("chatgpt.com")).toBeInTheDocument();
    expect(screen.queryByText("youtube.com")).not.toBeInTheDocument();
    expect(screen.getAllByText("100%").length).toBeGreaterThan(0);
  });

  it("defaults to duration descending and can sort by name", async () => {
    const user = userEvent.setup();
    render(
      <UsageTable
        sessions={[
          session({ id: "short", domain: "zeta.com", durationSeconds: 60 }),
          session({ id: "long", domain: "alpha.com", durationSeconds: 600 }),
        ]}
      />,
    );

    const initialRows = screen.getAllByRole("row");
    expect(within(initialRows[1]).getByText("alpha.com")).toBeInTheDocument();
    expect(within(initialRows[2]).getByText("zeta.com")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "이름 정렬" }));

    const sortedRows = screen.getAllByRole("row");
    expect(within(sortedRows[1]).getByText("alpha.com")).toBeInTheDocument();
    expect(within(sortedRows[2]).getByText("zeta.com")).toBeInTheDocument();
  });

  it("filters rows by search text and reports visible row count", async () => {
    const user = userEvent.setup();
    render(
      <UsageTable
        sessions={[
          session({ id: "chat", domain: "chatgpt.com", durationSeconds: 600 }),
          session({ id: "video", domain: "youtube.com", durationSeconds: 300 }),
        ]}
      />,
    );

    await user.type(screen.getByLabelText("사용 항목 검색"), "chat");

    expect(screen.getByText("1 / 2개 표시")).toBeInTheDocument();
    expect(screen.getByText("chatgpt.com")).toBeInTheDocument();
    expect(screen.queryByText("youtube.com")).not.toBeInTheDocument();
  });

  it("marks table rows with a narrow-layout card class", () => {
    render(<UsageTable sessions={[session({ domain: "chatgpt.com" })]} />);

    const row = screen.getByRole("row", { name: /chatgpt\.com/i });
    expect(row).toHaveClass("max-[640px]:block");
    expect(screen.getAllByText("비중").length).toBeGreaterThan(0);
  });
});
