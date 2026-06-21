use crate::collector::session_merger::ActivitySample;

pub trait ActiveWindowReader: Send + Sync {
    fn read_open_windows(&self) -> anyhow::Result<Vec<ActivitySample>>;
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
impl ActiveWindowReader for WindowsActiveWindowReader {
    fn read_open_windows(&self) -> anyhow::Result<Vec<ActivitySample>> {
        use anyhow::{bail, Context};
        use chrono::Utc;
        use windows::core::BOOL;
        use windows::Win32::Foundation::{HWND, LPARAM};
        use windows::core::PWSTR;
        use windows::Win32::System::Threading::{
            OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
            PROCESS_QUERY_LIMITED_INFORMATION,
        };
        use windows::Win32::UI::WindowsAndMessaging::{
            EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId,
            IsWindowVisible,
        };

        unsafe fn sample_for_window(
            hwnd: HWND,
            observed_at: chrono::DateTime<Utc>,
        ) -> anyhow::Result<Option<ActivitySample>> {
            if !IsWindowVisible(hwnd).as_bool() {
                return Ok(None);
            }
            let title_len = GetWindowTextLengthW(hwnd);
            if title_len <= 0 {
                return Ok(None);
            }
            let mut title_buf = vec![0u16; title_len as usize + 1];
            let copied = GetWindowTextW(hwnd, &mut title_buf);
            let window_title = String::from_utf16_lossy(&title_buf[..copied as usize]);
            if window_title.trim().is_empty() {
                return Ok(None);
            }

            let mut pid = 0u32;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == 0 {
                return Ok(None);
            }

            let process = OwnedProcessHandle(
                OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
                    .with_context(|| format!("OpenProcess failed for window pid {pid}"))?,
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
                format!("QueryFullProcessImageNameW failed for window pid {pid}")
            })?;

            let process_path = String::from_utf16_lossy(&process_buf[..process_len as usize]);
            let process_name = process_image_basename(&process_path);
            if is_browser_process(&process_name) {
                return Ok(None);
            }

            Ok(Some(ActivitySample {
                observed_at,
                instance_key: format!("window:{}", hwnd.0 as isize),
                app_name: process_name.clone(),
                process_name,
                window_title,
                domain: None,
                is_idle: false,
            }))
        }

        unsafe extern "system" fn enum_window(hwnd: HWND, lparam: LPARAM) -> BOOL {
            let samples = &mut *(lparam.0 as *mut Vec<ActivitySample>);
            let observed_at = Utc::now();
            if let Ok(Some(sample)) = sample_for_window(hwnd, observed_at) {
                samples.push(sample);
            }
            true.into()
        }

        unsafe {
            let mut samples = Vec::new();
            EnumWindows(Some(enum_window), LPARAM(&mut samples as *mut _ as isize))
                .context("EnumWindows failed")?;
            if samples.is_empty() {
                bail!("no open windows are available");
            }
            Ok(samples)
        }
    }
}

#[cfg(target_os = "windows")]
fn is_browser_process(process_name: &str) -> bool {
    matches!(
        process_name.to_ascii_lowercase().as_str(),
        "chrome.exe" | "msedge.exe" | "brave.exe" | "firefox.exe" | "opera.exe" | "vivaldi.exe"
    )
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
