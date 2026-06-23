import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { openMacosPermissionSettings } from "../../api/activityApi";
import type { PlatformPermissionStatus } from "../../types/activity";
import { MacosPermissionNotice } from "./MacosPermissionNotice";

vi.mock("../../api/activityApi", () => ({
  openMacosPermissionSettings: vi.fn(),
}));

function status(overrides: Partial<PlatformPermissionStatus> = {}): PlatformPermissionStatus {
  return {
    platform: "macos",
    accessibilityGranted: false,
    screenRecordingGranted: false,
    accessibilityRequiredReason: "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.",
    screenRecordingRequiredReason:
      "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다. FlowPilot은 화면 이미지를 저장하지 않습니다.",
    canPromptAccessibility: true,
    canPromptScreenRecording: true,
    ...overrides,
  };
}

describe("MacosPermissionNotice", () => {
  beforeEach(() => {
    vi.mocked(openMacosPermissionSettings).mockResolvedValue();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("renders Korean guidance when macOS permissions are missing", () => {
    render(<MacosPermissionNotice permissionStatus={status()} />);

    expect(screen.getByText("macOS 권한 설정이 필요합니다")).toBeInTheDocument();
    expect(screen.getByText(/손쉬운 사용 권한/)).toBeInTheDocument();
    expect(screen.getByText(/화면 기록 권한/)).toBeInTheDocument();
    expect(screen.getByText(/FlowPilot을 허용한 뒤 앱을 다시 실행/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "손쉬운 사용 열기" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "화면 기록 열기" })).toBeInTheDocument();
  });

  it("opens the selected macOS permission pane from the notice", async () => {
    const user = userEvent.setup();
    render(
      <MacosPermissionNotice
        permissionStatus={status({
          screenRecordingGranted: true,
        })}
      />,
    );

    await user.click(screen.getByRole("button", { name: "손쉬운 사용 열기" }));

    expect(openMacosPermissionSettings).toHaveBeenCalledWith("accessibility");
    expect(screen.queryByRole("button", { name: "화면 기록 열기" })).not.toBeInTheDocument();
  });

  it("does not render outside macOS", () => {
    const { container } = render(
      <MacosPermissionNotice permissionStatus={status({ platform: "windows" })} />,
    );

    expect(container).toBeEmptyDOMElement();
  });

  it("does not render when both permissions are granted", () => {
    const { container } = render(
      <MacosPermissionNotice
        permissionStatus={status({
          accessibilityGranted: true,
          screenRecordingGranted: true,
        })}
      />,
    );

    expect(container).toBeEmptyDOMElement();
  });
});
