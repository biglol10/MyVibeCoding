use std::sync::{Arc, Mutex};
use std::time::Duration;

use app_state::{AppState, TrackingStatus};
use storage::repository::Repository;
use tauri::Manager;

pub mod app_state;
pub mod browser_bridge;
pub mod collector;
pub mod commands;
pub mod domain;
pub mod export;
pub mod permissions;
pub mod storage;
pub mod tray;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    if let Err(err) = tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::create_rule,
            commands::export_today_csv,
            commands::get_today_summary,
            commands::get_today_sessions,
            commands::list_rules,
            commands::pause_tracking,
            commands::resume_tracking,
            commands::update_rule,
            permissions::get_platform_permission_status,
            permissions::open_macos_permission_settings
        ])
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            let app_data_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&app_data_dir)?;
            let repository = Arc::new(Mutex::new(Repository::open(
                app_data_dir.join("time-manager.sqlite3"),
            )?));
            let tracking_status = Arc::new(Mutex::new(TrackingStatus { paused_until: None }));
            if let Err(err) = browser_bridge::start_browser_bridge(repository.clone()) {
                log::warn!("optional browser bridge disabled: {err}");
            }
            #[cfg(target_os = "windows")]
            collector::service::CollectorService::for_windows(
                Duration::from_secs(5),
                repository.clone(),
                tracking_status.clone(),
            )
            .start();
            #[cfg(target_os = "macos")]
            collector::service::CollectorService::new(
                Duration::from_secs(5),
                collector::macos::MacosActivitySnapshotReader::new(),
                repository.clone(),
                tracking_status.clone(),
            )
            .start();
            app.manage(AppState {
                repository,
                tracking_status,
            });
            tray::setup_tray(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(target_os = "macos")]
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
    {
        eprintln!("error while running tauri application: {err}");
    }
}
