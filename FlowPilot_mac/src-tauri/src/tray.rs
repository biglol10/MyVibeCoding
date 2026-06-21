use chrono::{Duration, Utc};
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    App, Manager,
};

use crate::app_state::AppState;

pub fn setup_tray(app: &mut App) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open Dashboard", true, None::<&str>)?;
    let pause_15 = MenuItem::with_id(app, "pause_15", "Pause 15 minutes", true, None::<&str>)?;
    let pause_60 = MenuItem::with_id(app, "pause_60", "Pause 1 hour", true, None::<&str>)?;
    let pause_day = MenuItem::with_id(app, "pause_day", "Pause 24 hours", true, None::<&str>)?;
    let resume = MenuItem::with_id(app, "resume", "Resume Tracking", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[&open, &pause_15, &pause_60, &pause_day, &resume, &quit],
    )?;

    let mut tray_builder = TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("FlowPilot")
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| {
            let id = event.id().as_ref();
            match id {
                "open" => {
                    if let Some(window) = app.get_webview_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                "pause_15" => set_pause(app, Duration::minutes(15)),
                "pause_60" => set_pause(app, Duration::hours(1)),
                "pause_day" => set_pause(app, Duration::days(1)),
                "resume" => clear_pause(app),
                "quit" => app.exit(0),
                _ => {}
            }
        });

    if let Some(icon) = app.default_window_icon().cloned() {
        tray_builder = tray_builder.icon(icon);
    }

    tray_builder.build(app)?;

    Ok(())
}

fn set_pause(app: &tauri::AppHandle, duration: Duration) {
    let state = app.state::<AppState>();
    if let Ok(mut status) = state.tracking_status.lock() {
        status.paused_until = Some(Utc::now() + duration);
    } else {
        log::warn!("Tracking status lock poisoned while pausing from tray.");
    };
}

fn clear_pause(app: &tauri::AppHandle) {
    let state = app.state::<AppState>();
    if let Ok(mut status) = state.tracking_status.lock() {
        status.paused_until = None;
    } else {
        log::warn!("Tracking status lock poisoned while resuming from tray.");
    };
}
