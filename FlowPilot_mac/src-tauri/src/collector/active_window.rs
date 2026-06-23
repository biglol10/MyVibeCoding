#[cfg(any(test, target_os = "windows"))]
use crate::collector::session_merger::ActivitySample;
#[cfg(any(test, target_os = "windows"))]
use crate::collector::snapshot::ActivitySnapshot;
#[cfg(target_os = "windows")]
use crate::collector::snapshot::ActivitySnapshotReader;

#[cfg(any(test, target_os = "windows"))]
fn snapshot_from_active_window_sample(sample: ActivitySample) -> ActivitySnapshot {
    ActivitySnapshot::from_primary(sample)
}

#[cfg(target_os = "windows")]
pub struct WindowsActiveWindowReader;

#[cfg(target_os = "windows")]
struct OwnedProcessHandle(windows::Win32::Foundation::HANDLE);

#[cfg(target_os = "windows")]
impl OwnedProcessHandle {
    fn get(&self) -> windows::Win32::Foundation::HANDLE {
        self.0
    }
}

#[cfg(target_os = "windows")]
impl Drop for OwnedProcessHandle {
    fn drop(&mut self) {
        unsafe {
            let _ = windows::Win32::Foundation::CloseHandle(self.0);
        }
    }
}

#[cfg(target_os = "windows")]
fn process_image_basename(image_path: &str) -> String {
    std::path::Path::new(image_path)
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or(image_path)
        .to_string()
}

#[cfg(target_os = "windows")]
impl ActivitySnapshotReader for WindowsActiveWindowReader {
    fn read_snapshot(&self) -> anyhow::Result<ActivitySnapshot> {
        use anyhow::{bail, Context};
        use chrono::Utc;
        use windows::core::PWSTR;
        use windows::Win32::System::Threading::{
            OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
            PROCESS_QUERY_LIMITED_INFORMATION,
        };
        use windows::Win32::UI::WindowsAndMessaging::{
            GetForegroundWindow, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId,
        };

        unsafe {
            let hwnd = GetForegroundWindow();
            if hwnd.is_invalid() {
                bail!("no foreground window is available");
            }

            let title_len = GetWindowTextLengthW(hwnd);
            if title_len < 0 {
                bail!("foreground window title length was invalid");
            }
            let mut title_buf = vec![0u16; title_len as usize + 1];
            let copied = GetWindowTextW(hwnd, &mut title_buf);
            let window_title = String::from_utf16_lossy(&title_buf[..copied as usize]);

            let mut pid = 0u32;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == 0 {
                bail!("foreground window did not report a process id");
            }

            let process = OwnedProcessHandle(
                OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
                    .with_context(|| format!("OpenProcess failed for foreground pid {pid}"))?,
            );

            let mut process_buf = vec![0u16; 32_768];
            let mut process_len = process_buf.len() as u32;
            QueryFullProcessImageNameW(
                process.get(),
                PROCESS_NAME_WIN32,
                PWSTR(process_buf.as_mut_ptr()),
                &mut process_len,
            )
            .with_context(|| {
                format!("QueryFullProcessImageNameW failed for foreground pid {pid}")
            })?;

            let process_path = String::from_utf16_lossy(&process_buf[..process_len as usize]);
            let process_name = process_image_basename(&process_path);

            Ok(snapshot_from_active_window_sample(ActivitySample {
                observed_at: Utc::now(),
                app_name: process_name.clone(),
                process_name,
                window_title,
                domain: None,
                is_idle: false,
            }))
        }
    }
}

#[cfg(test)]
mod snapshot_tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn active_window_snapshot_contains_only_primary_observation() {
        let sample = ActivitySample {
            observed_at: Utc::now(),
            app_name: "Code".into(),
            process_name: "Code.exe".into(),
            window_title: "FlowPilot".into(),
            domain: None,
            is_idle: false,
        };

        let snapshot = snapshot_from_active_window_sample(sample.clone());

        assert_eq!(snapshot.primary, sample);
        assert_eq!(snapshot.visible_windows.len(), 1);
        assert!(snapshot.visible_windows[0].is_primary);
    }
}

#[cfg(all(test, target_os = "windows"))]
mod tests {
    use super::process_image_basename;

    #[test]
    fn extracts_process_image_basename_from_windows_path() {
        assert_eq!(
            process_image_basename(r"C:\Program Files\FlowPilot\flowpilot.exe"),
            "flowpilot.exe"
        );
    }
}
