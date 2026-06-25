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
  it("groups sessions by hour and shows readable cards", () => {
    render(
      <DayTimeline
        sessions={[
          session({
            id: "codex-1",
            startedAt: "2026-06-25T11:26:00+09:00",
            endedAt: "2026-06-25T12:15:00+09:00",
            durationSeconds: 2940,
            appName: "Codex",
            processName: "Codex",
            windowTitle: "Codex",
            domain: null,
            category: "productive",
            matchedRuleId: "user:app:Codex",
          }),
          session({
            id: "capture",
            startedAt: "2026-06-25T12:15:00+09:00",
            endedAt: "2026-06-25T13:23:00+09:00",
            durationSeconds: 4020,
            appName: "CaptureStudio",
            processName: "CaptureStudio",
            windowTitle: "CaptureStudio",
            domain: null,
            category: "uncategorized",
          }),
          session({
            id: "codex-2",
            startedAt: "2026-06-25T13:23:00+09:00",
            endedAt: "2026-06-25T14:18:00+09:00",
            durationSeconds: 3300,
            appName: "Codex",
            processName: "Codex",
            windowTitle: "Codex",
            domain: null,
            category: "productive",
            matchedRuleId: "user:app:Codex",
          }),
          session({
            id: "ghost",
            startedAt: "2026-06-25T14:18:00+09:00",
            endedAt: "2026-06-25T14:18:00+09:00",
            durationSeconds: 0,
            appName: "GhostApp",
            processName: "GhostApp",
            windowTitle: "GhostApp",
            domain: null,
            category: "uncategorized",
          }),
        ]}
      />,
    );

    expect(screen.getByRole("heading", { name: "오늘 타임라인" })).toBeInTheDocument();
    expect(screen.getByText("11시")).toBeInTheDocument();
    expect(screen.getByText("12시")).toBeInTheDocument();
    expect(screen.getByText("13시")).toBeInTheDocument();
    expect(screen.getByText("11:26 - 12:15")).toBeInTheDocument();
    expect(screen.getByText("12:15 - 13:23")).toBeInTheDocument();
    expect(screen.getByText("13:23 - 14:18")).toBeInTheDocument();
    expect(screen.getByText("49m")).toBeInTheDocument();
    expect(screen.getByText("1h 7m")).toBeInTheDocument();
    expect(screen.getByText("55m")).toBeInTheDocument();
    expect(screen.getAllByText("생산적")).toHaveLength(2);
    expect(screen.getAllByText("검토 필요")).toHaveLength(1);
    expect(screen.queryByText("GhostApp")).not.toBeInTheDocument();
  });
});
