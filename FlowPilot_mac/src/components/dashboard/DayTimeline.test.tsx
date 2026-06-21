import { render, screen } from "@testing-library/react";
import { DayTimeline } from "./DayTimeline";
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

describe("DayTimeline", () => {
  it("exposes timeline segments as a structured list", () => {
    render(<DayTimeline sessions={[session({ id: "one" }), session({ id: "two", domain: "docs.example.com" })]} />);

    expect(screen.getByRole("list", { name: "오늘 활동 세션 타임라인" })).toBeInTheDocument();
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
  });
});
