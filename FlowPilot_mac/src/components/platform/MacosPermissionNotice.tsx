import { useState } from "react";
import { ExternalLink } from "lucide-react";
import { openMacosPermissionSettings } from "../../api/activityApi";
import type { PlatformPermissionStatus } from "../../types/activity";
import { Alert, AlertDescription, AlertTitle } from "../ui/alert";
import { Button } from "../ui/button";

interface MacosPermissionNoticeProps {
  permissionStatus: PlatformPermissionStatus | null;
}

export function MacosPermissionNotice({ permissionStatus }: MacosPermissionNoticeProps) {
  const [openError, setOpenError] = useState<string | null>(null);

  if (!permissionStatus || permissionStatus.platform !== "macos") {
    return null;
  }

  const missingAccessibility = !permissionStatus.accessibilityGranted;
  const missingScreenRecording = !permissionStatus.screenRecordingGranted;

  if (!missingAccessibility && !missingScreenRecording) {
    return null;
  }

  const showAccessibilityButton = missingAccessibility && permissionStatus.canPromptAccessibility;
  const showScreenRecordingButton = missingScreenRecording && permissionStatus.canPromptScreenRecording;

  async function handleOpenAccessibility() {
    try {
      setOpenError(null);
      await openMacosPermissionSettings("accessibility");
    } catch {
      setOpenError("시스템 설정을 열지 못했습니다. 개인정보 보호 및 보안에서 직접 권한 화면을 열어 주세요.");
    }
  }

  async function handleOpenScreenRecording() {
    try {
      setOpenError(null);
      await openMacosPermissionSettings("screenRecording");
    } catch {
      setOpenError("시스템 설정을 열지 못했습니다. 개인정보 보호 및 보안에서 직접 권한 화면을 열어 주세요.");
    }
  }

  return (
    <Alert className="mb-4" variant="warning" aria-labelledby="macos-permission-title">
      <AlertTitle id="macos-permission-title">macOS 권한 설정이 필요합니다</AlertTitle>
      <AlertDescription className="grid gap-2">
        <p>시스템 설정 &gt; 개인정보 보호 및 보안에서 FlowPilot을 허용한 뒤 앱을 다시 실행해 주세요.</p>
        <ul className="m-0 grid gap-1 pl-5">
          {missingAccessibility ? <li>{permissionStatus.accessibilityRequiredReason}</li> : null}
          {missingScreenRecording ? <li>{permissionStatus.screenRecordingRequiredReason}</li> : null}
        </ul>
        {showAccessibilityButton || showScreenRecordingButton ? (
          <div className="flex flex-wrap gap-2 pt-1">
            {showAccessibilityButton ? (
              <Button size="sm" type="button" onClick={() => void handleOpenAccessibility()} variant="outline">
                <ExternalLink aria-hidden="true" className="size-4" />
                손쉬운 사용 열기
              </Button>
            ) : null}
            {showScreenRecordingButton ? (
              <Button size="sm" type="button" onClick={() => void handleOpenScreenRecording()} variant="outline">
                <ExternalLink aria-hidden="true" className="size-4" />
                화면 기록 열기
              </Button>
            ) : null}
          </div>
        ) : null}
        {openError ? <p className="text-xs font-semibold text-amber-950">{openError}</p> : null}
      </AlertDescription>
    </Alert>
  );
}
