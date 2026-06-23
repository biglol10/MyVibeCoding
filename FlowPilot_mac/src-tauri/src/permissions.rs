use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MacosPermissionPane {
    Accessibility,
    ScreenRecording,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformPermissionStatus {
    pub platform: String,
    pub accessibility_granted: bool,
    pub screen_recording_granted: bool,
    pub accessibility_required_reason: String,
    pub screen_recording_required_reason: String,
    pub can_prompt_accessibility: bool,
    pub can_prompt_screen_recording: bool,
}

#[tauri::command]
pub fn get_platform_permission_status() -> PlatformPermissionStatus {
    platform_permission_status()
}

#[tauri::command]
pub fn open_macos_permission_settings(pane: MacosPermissionPane) -> Result<(), String> {
    open_system_settings_url(macos_permission_settings_url(pane)).or_else(|primary_error| {
        open_system_settings_url(macos_privacy_security_settings_url()).map_err(|fallback_error| {
            format!(
                "failed to open macOS permission settings: {primary_error}; fallback failed: {fallback_error}"
            )
        })
    })
}

pub fn platform_permission_status() -> PlatformPermissionStatus {
    PlatformPermissionStatus {
        platform: platform_name().into(),
        accessibility_granted: accessibility_granted(),
        screen_recording_granted: screen_recording_granted(),
        accessibility_required_reason:
            "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.".into(),
        screen_recording_required_reason:
            "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다. FlowPilot은 화면 이미지를 저장하지 않습니다."
                .into(),
        can_prompt_accessibility: cfg!(target_os = "macos"),
        can_prompt_screen_recording: cfg!(target_os = "macos"),
    }
}

fn macos_permission_settings_url(pane: MacosPermissionPane) -> &'static str {
    match pane {
        MacosPermissionPane::Accessibility => {
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        MacosPermissionPane::ScreenRecording => {
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }
}

fn macos_privacy_security_settings_url() -> &'static str {
    "x-apple.systempreferences:com.apple.preference.security"
}

#[cfg(target_os = "macos")]
fn open_system_settings_url(url: &str) -> Result<(), String> {
    let status = std::process::Command::new("open")
        .arg(url)
        .status()
        .map_err(|error| error.to_string())?;

    if status.success() {
        Ok(())
    } else {
        Err(format!("open exited with status {status}"))
    }
}

#[cfg(not(target_os = "macos"))]
fn open_system_settings_url(_url: &str) -> Result<(), String> {
    Err("macOS permission settings can only be opened on macOS.".into())
}

fn platform_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "other"
    }
}

#[cfg(target_os = "macos")]
fn accessibility_granted() -> bool {
    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> u8;
    }

    unsafe { AXIsProcessTrusted() != 0 }
}

#[cfg(not(target_os = "macos"))]
fn accessibility_granted() -> bool {
    true
}

#[cfg(target_os = "macos")]
fn screen_recording_granted() -> bool {
    core_graphics::access::ScreenCaptureAccess::default().preflight()
}

#[cfg(not(target_os = "macos"))]
fn screen_recording_granted() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permission_status_serializes_with_camel_case_fields() {
        let status = PlatformPermissionStatus {
            platform: "macos".into(),
            accessibility_granted: false,
            screen_recording_granted: true,
            accessibility_required_reason:
                "앱과 창 제목을 정확히 기록하려면 손쉬운 사용 권한이 필요합니다.".into(),
            screen_recording_required_reason:
                "열려 있는 창 목록과 제목을 확인하려면 화면 기록 권한이 필요할 수 있습니다.".into(),
            can_prompt_accessibility: true,
            can_prompt_screen_recording: true,
        };

        let serialized = serde_json::to_value(status).expect("serialized");

        assert_eq!(serialized["accessibilityGranted"], false);
        assert_eq!(serialized["screenRecordingGranted"], true);
        assert_eq!(serialized["canPromptAccessibility"], true);
        assert!(serialized["accessibility_required_reason"].is_null());
    }

    #[test]
    fn permission_panes_map_to_specific_system_settings_urls() {
        assert_eq!(
            macos_permission_settings_url(MacosPermissionPane::Accessibility),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        );
        assert_eq!(
            macos_permission_settings_url(MacosPermissionPane::ScreenRecording),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        );
    }
}
