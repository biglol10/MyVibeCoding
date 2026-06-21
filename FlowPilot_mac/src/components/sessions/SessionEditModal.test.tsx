import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SessionEditModal } from "./SessionEditModal";
import type { ReportActivitySession } from "../../types/activity";

function session(): ReportActivitySession {
  return {
    id: "session-1",
    startedAt: "2026-06-19T09:00:00.000Z",
    endedAt: "2026-06-19T09:30:00.000Z",
    durationSeconds: 1800,
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "Lecture",
    domain: "youtube.com",
    isIdle: false,
    category: "unproductive",
    matchedRuleId: "builtin:domain:youtube.com",
    categorySource: "automatic",
    displayName: "youtube.com",
    note: null,
  };
}

describe("SessionEditModal", () => {
  it("saves a category, display name, and note override", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();

    render(<SessionEditModal session={session()} onClose={vi.fn()} onReset={vi.fn()} onSave={onSave} />);

    await user.selectOptions(screen.getByLabelText("분류"), "productive");
    await user.clear(screen.getByLabelText("표시 이름"));
    await user.type(screen.getByLabelText("표시 이름"), "강의 준비");
    await user.type(screen.getByLabelText("메모"), "강의 영상");
    await user.click(screen.getByRole("button", { name: /저장/ }));

    expect(onSave).toHaveBeenCalledWith({
      categoryOverride: "productive",
      displayNameOverride: "강의 준비",
      note: "강의 영상",
      sessionId: "session-1",
    });
  });
});
