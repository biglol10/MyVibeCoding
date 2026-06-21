pub trait IdleReader: Send + Sync {
    fn is_idle(&self) -> anyhow::Result<bool>;
}

#[cfg(target_os = "windows")]
pub struct WindowsIdleReader {
    pub idle_threshold_seconds: u32,
}

#[cfg(target_os = "windows")]
fn idle_seconds_since(now: u32, last_input: u32) -> u32 {
    now.wrapping_sub(last_input) / 1000
}

#[cfg(target_os = "windows")]
impl IdleReader for WindowsIdleReader {
    fn is_idle(&self) -> anyhow::Result<bool> {
        use anyhow::Context;
        use windows::Win32::System::SystemInformation::GetTickCount;
        use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};

        unsafe {
            let mut info = LASTINPUTINFO {
                cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
                dwTime: 0,
            };
            GetLastInputInfo(&mut info)
                .ok()
                .context("GetLastInputInfo failed")?;

            let now = GetTickCount();
            Ok(idle_seconds_since(now, info.dwTime) >= self.idle_threshold_seconds)
        }
    }
}

#[cfg(all(test, target_os = "windows"))]
mod tests {
    use super::*;

    #[test]
    fn idle_seconds_handles_tick_count_wrap() {
        assert_eq!(idle_seconds_since(2_000, u32::MAX - 999), 3);
    }
}
