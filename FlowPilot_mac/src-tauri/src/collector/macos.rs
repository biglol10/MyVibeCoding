use anyhow::anyhow;

use crate::collector::session_merger::ActivitySample;
use crate::collector::snapshot::{
    choose_primary_observation, ActivitySnapshot, ActivitySnapshotReader, WindowObservation,
};

pub struct MacosActivitySnapshotReader {
    own_bundle_identifier: Option<String>,
}

impl MacosActivitySnapshotReader {
    pub fn new() -> Self {
        Self {
            own_bundle_identifier: Some("app.flowpilot.desktop".into()),
        }
    }
}

impl Default for MacosActivitySnapshotReader {
    fn default() -> Self {
        Self::new()
    }
}

impl ActivitySnapshotReader for MacosActivitySnapshotReader {
    fn read_snapshot(&self) -> anyhow::Result<ActivitySnapshot> {
        let mut observations = collect_window_observations()?;
        let primary_index =
            choose_primary_observation(&observations, self.own_bundle_identifier.as_deref())
                .and_then(|selected| {
                    observations
                        .iter()
                        .position(|observation| observation == selected)
                })
                .ok_or_else(|| anyhow!("no macOS activity observation is available"))?;

        for (index, observation) in observations.iter_mut().enumerate() {
            observation.is_primary = index == primary_index;
        }

        let primary = sample_from_observation(&observations[primary_index]);

        Ok(ActivitySnapshot {
            primary,
            visible_windows: observations,
        })
    }
}

fn sample_from_observation(observation: &WindowObservation) -> ActivitySample {
    ActivitySample {
        observed_at: observation.observed_at,
        app_name: observation.app_name.clone(),
        process_name: observation.process_name.clone(),
        window_title: observation
            .window_title
            .clone()
            .filter(|title| !title.trim().is_empty())
            .unwrap_or_else(|| observation.app_name.clone()),
        domain: None,
        is_idle: false,
    }
}

#[cfg(target_os = "macos")]
fn collect_window_observations() -> anyhow::Result<Vec<WindowObservation>> {
    use chrono::Utc;
    use objc2_app_kit::NSWorkspace;

    let observed_at = Utc::now();
    let workspace = NSWorkspace::sharedWorkspace();
    let frontmost_pid = workspace
        .frontmostApplication()
        .map(|application| application.processIdentifier());
    let applications = workspace.runningApplications();
    let mut observations = Vec::new();

    for application in applications.iter() {
        let app_name = application
            .localizedName()
            .map(|name| name.to_string())
            .filter(|name| !name.trim().is_empty());
        let Some(app_name) = app_name else {
            continue;
        };

        let pid = application.processIdentifier();
        if pid < 0 {
            continue;
        }

        let bundle_identifier = application
            .bundleIdentifier()
            .map(|identifier| identifier.to_string());
        let is_frontmost = frontmost_pid == Some(pid);
        let window_title = if is_frontmost {
            focused_window_title(pid)
        } else {
            None
        };

        observations.push(WindowObservation {
            observed_at,
            app_name: app_name.clone(),
            process_name: app_name,
            pid: Some(pid as u32),
            bundle_identifier,
            window_title,
            is_visible: is_frontmost,
            is_frontmost,
            is_primary: false,
        });
    }

    Ok(observations)
}

#[cfg(not(target_os = "macos"))]
fn collect_window_observations() -> anyhow::Result<Vec<WindowObservation>> {
    Err(anyhow!(
        "macOS activity collection is only available on macOS"
    ))
}

fn non_empty_title(title: String) -> Option<String> {
    let trimmed = title.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

#[cfg(target_os = "macos")]
fn focused_window_title(pid: i32) -> Option<String> {
    use core_foundation::base::{CFType, CFTypeRef, TCFType};
    use core_foundation::string::{CFString, CFStringRef};
    use std::ptr;

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXUIElementCreateApplication(pid: i32) -> CFTypeRef;
        fn AXUIElementCopyAttributeValue(
            element: CFTypeRef,
            attribute: CFStringRef,
            value: *mut CFTypeRef,
        ) -> i32;
    }

    fn copy_attribute(element: CFTypeRef, name: &str) -> Option<CFType> {
        const AX_ERROR_SUCCESS: i32 = 0;

        let attribute = CFString::new(name);
        let mut value: CFTypeRef = ptr::null();
        let result = unsafe {
            AXUIElementCopyAttributeValue(element, attribute.as_concrete_TypeRef(), &mut value)
        };

        if result == AX_ERROR_SUCCESS && !value.is_null() {
            Some(unsafe { CFType::wrap_under_create_rule(value) })
        } else {
            None
        }
    }

    if pid < 0 {
        return None;
    }

    let app_ref = unsafe { AXUIElementCreateApplication(pid) };
    if app_ref.is_null() {
        return None;
    }

    let app = unsafe { CFType::wrap_under_create_rule(app_ref) };
    let window = copy_attribute(app.as_CFTypeRef(), "AXFocusedWindow")?;
    let title = copy_attribute(window.as_CFTypeRef(), "AXTitle")?
        .downcast_into::<CFString>()?
        .to_string();

    non_empty_title(title)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn sample_from_observation_preserves_app_process_and_title() {
        let observed_at = chrono::Utc.with_ymd_and_hms(2026, 6, 19, 9, 0, 0).unwrap();
        let observation = crate::collector::snapshot::WindowObservation {
            observed_at,
            app_name: "Safari".into(),
            process_name: "Safari".into(),
            pid: Some(123),
            bundle_identifier: Some("com.apple.Safari".into()),
            window_title: Some("Apple Developer".into()),
            is_visible: true,
            is_frontmost: true,
            is_primary: true,
        };

        let sample = sample_from_observation(&observation);

        assert_eq!(sample.app_name, "Safari");
        assert_eq!(sample.process_name, "Safari");
        assert_eq!(sample.window_title, "Apple Developer");
        assert_eq!(sample.domain, None);
        assert!(!sample.is_idle);
    }

    #[test]
    fn sample_from_observation_uses_app_name_when_title_is_missing() {
        let observed_at = chrono::Utc.with_ymd_and_hms(2026, 6, 19, 9, 0, 0).unwrap();
        let observation = crate::collector::snapshot::WindowObservation {
            observed_at,
            app_name: "Notes".into(),
            process_name: "Notes".into(),
            pid: None,
            bundle_identifier: None,
            window_title: None,
            is_visible: true,
            is_frontmost: true,
            is_primary: true,
        };

        let sample = sample_from_observation(&observation);

        assert_eq!(sample.window_title, "Notes");
    }

    #[test]
    fn non_empty_title_trims_blank_titles() {
        assert_eq!(
            non_empty_title("  Project Plan  ".into()).as_deref(),
            Some("Project Plan")
        );
        assert_eq!(non_empty_title("   ".into()), None);
    }
}
