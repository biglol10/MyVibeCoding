import { render, screen } from "@testing-library/react";
import type { ActivitySession } from "../../types/activity";
import { DayTimeline } from "./DayTimeline";

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

describe("DayTimeline", () => {
  it("exposes timeline segments as a structured list", () => {
    render(<DayTimeline sessions={[session({ id: "one" }), session({ id: "two", domain: "docs.example.com" })]} />);

    expect(screen.getByRole("list")).toBeInTheDocument();
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
  });

  it("excludes ignored sessions from timeline segments", () => {
    render(
      <DayTimeline
        sessions={[
          session({ id: "productive", domain: "docs.example.com" }),
          session({ id: "ignored", category: "ignored", domain: "ignored.example" }),
        ]}
      />,
    );

    expect(screen.getAllByRole("listitem")).toHaveLength(1);
    expect(screen.getByLabelText(/docs\.example\.com/i)).toBeInTheDocument();
    expect(screen.queryByLabelText(/ignored\.example/i)).not.toBeInTheDocument();
  });
});
