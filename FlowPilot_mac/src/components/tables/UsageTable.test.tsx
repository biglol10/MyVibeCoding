import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
import type { ActivitySession } from "../../types/activity";
import { UsageTable } from "./UsageTable";

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

    expect(within(row).getByText(CATEGORY_LABELS.productive)).toBeInTheDocument();
    expect(within(row).queryByText(CATEGORY_LABELS.unproductive)).not.toBeInTheDocument();
  });

  it("shows idle when a destination row is entirely idle", () => {
    render(<UsageTable sessions={[session({ isIdle: true })]} />);

    expect(screen.getByText("유휴")).toBeInTheDocument();
  });

  it("renders category badges as compact single-line status chips", () => {
    render(<UsageTable sessions={[session({ category: "uncategorized" })]} />);

    const badge = screen.getByText(CATEGORY_LABELS.uncategorized).closest("[data-slot='badge']");

    expect(badge).toHaveClass("h-7");
    expect(badge).toHaveClass("rounded-md");
    expect(badge).toHaveClass("whitespace-nowrap");
    expect(badge).not.toHaveClass("rounded-full");
  });

  it("excludes ignored sessions from usage rows", () => {
    render(
      <UsageTable
        sessions={[
          session({ id: "productive", domain: "docs.example.com", durationSeconds: 600 }),
          session({ id: "ignored", category: "ignored", domain: "ignored.example", durationSeconds: 300 }),
        ]}
      />,
    );

    expect(screen.getByRole("row", { name: /docs\.example\.com/i })).toBeInTheDocument();
    expect(screen.queryByRole("row", { name: /ignored\.example/i })).not.toBeInTheDocument();
  });

  it("sorts rows by column headers", async () => {
    const user = userEvent.setup();

    render(
      <UsageTable
        sessions={[
          session({ id: "short", domain: "zeta.example", durationSeconds: 60 }),
          session({ id: "long", domain: "alpha.example", durationSeconds: 120 }),
        ]}
      />,
    );

    await user.click(screen.getByRole("button", { name: /이름/ }));

    const rows = screen.getAllByRole("row").slice(1);

    expect(within(rows[0]).getByText("alpha.example")).toBeInTheDocument();
    expect(within(rows[1]).getByText("zeta.example")).toBeInTheDocument();
  });

  it("shows an explicit empty state when there are no rows", () => {
    render(<UsageTable sessions={[]} />);

    expect(screen.getByText(EMPTY_STATE_TEXT.noDestinations)).toBeInTheDocument();
  });
});
