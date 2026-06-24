use chrono::{Duration, Utc};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    App, AppHandle, Manager, Wry,
};

use crate::app_state::AppState;
use crate::commands::TodaySummaryDto;

#[derive(Clone)]
struct TraySummaryItems {
    total: MenuItem<Wry>,
    productive: MenuItem<Wry>,
    unproductive: MenuItem<Wry>,
    neutral: MenuItem<Wry>,
    uncategorized: MenuItem<Wry>,
    status: MenuItem<Wry>,
}

#[derive(Debug, PartialEq, Eq)]
struct SummaryLines {
    total: String,
    productive: String,
    unproductive: String,
    neutral: String,
    uncategorized: String,
    status: String,
}

pub fn setup_tray(app: &mut App) -> tauri::Result<()> {
    let summary_items = TraySummaryItems {
        total: MenuItem::with_id(app, "summary_total", "오늘 기록: 계산 중", false, None::<&str>)?,
        productive: MenuItem::with_id(
            app,
            "summary_productive",
            "생산적: 계산 중",
            false,
            None::<&str>,
        )?,
        unproductive: MenuItem::with_id(
            app,
            "summary_unproductive",
            "비생산: 계산 중",
            false,
            None::<&str>,
        )?,
        neutral: MenuItem::with_id(app, "summary_neutral", "중립: 계산 중", false, None::<&str>)?,
        uncategorized: MenuItem::with_id(
            app,
            "summary_uncategorized",
            "미분류: 계산 중",
            false,
            None::<&str>,
        )?,
        status: MenuItem::with_id(app, "summary_status", "상태: 확인 중", false, None::<&str>)?,
    };
    let separator_top = PredefinedMenuItem::separator(app)?;
    let separator_actions = PredefinedMenuItem::separator(app)?;
    let open = MenuItem::with_id(app, "open", "대시보드 열기", true, None::<&str>)?;
    let pause_15 = MenuItem::with_id(app, "pause_15", "15분 일시정지", true, None::<&str>)?;
    let pause_60 = MenuItem::with_id(app, "pause_60", "1시간 일시정지", true, None::<&str>)?;
    let pause_day = MenuItem::with_id(app, "pause_day", "24시간 일시정지", true, None::<&str>)?;
    let resume = MenuItem::with_id(app, "resume", "기록 재개", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "종료", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &summary_items.total,
            &summary_items.productive,
            &summary_items.unproductive,
            &summary_items.neutral,
            &summary_items.uncategorized,
            &summary_items.status,
            &separator_top,
            &open,
            &separator_actions,
            &pause_15,
            &pause_60,
            &pause_day,
            &resume,
            &quit,
        ],
    )?;

    refresh_tray_summary(&app.handle().clone(), &summary_items);
    start_tray_summary_refresh_loop(app.handle().clone(), summary_items.clone());

    let mut tray_builder = TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("FlowPilot")
        .show_menu_on_left_click(true)
        .on_tray_icon_event({
            let summary_items = summary_items.clone();
            move |tray, _event| {
                refresh_tray_summary(&tray.app_handle().clone(), &summary_items);
            }
        })
        .on_menu_event({
            let summary_items = summary_items.clone();
            move |app, event| {
                let id = event.id().as_ref();
                match id {
                    "open" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "pause_15" => {
                        set_pause(app, Duration::minutes(15));
                        refresh_tray_summary(app, &summary_items);
                    }
                    "pause_60" => {
                        set_pause(app, Duration::hours(1));
                        refresh_tray_summary(app, &summary_items);
                    }
                    "pause_day" => {
                        set_pause(app, Duration::days(1));
                        refresh_tray_summary(app, &summary_items);
                    }
                    "resume" => {
                        clear_pause(app);
                        refresh_tray_summary(app, &summary_items);
                    }
                    "quit" => app.exit(0),
                    _ => {}
                }
            }
        });

    if let Some(icon) = app.default_window_icon().cloned() {
        tray_builder = tray_builder.icon(icon);
    }

    tray_builder.build(app)?;

    Ok(())
}

fn refresh_tray_summary(app: &AppHandle, items: &TraySummaryItems) {
    match read_today_summary(app) {
        Ok((summary, status)) => {
            let lines = build_summary_lines(&summary, &status);
            let _ = items.total.set_text(lines.total);
            let _ = items.productive.set_text(lines.productive);
            let _ = items.unproductive.set_text(lines.unproductive);
            let _ = items.neutral.set_text(lines.neutral);
            let _ = items.uncategorized.set_text(lines.uncategorized);
            let _ = items.status.set_text(lines.status);
        }
        Err(error) => {
            log::warn!("failed to refresh menu bar summary: {error}");
            let _ = items.total.set_text("오늘 기록: 불러올 수 없음");
            let _ = items.productive.set_text("생산적: -");
            let _ = items.unproductive.set_text("비생산: -");
            let _ = items.neutral.set_text("중립: -");
            let _ = items.uncategorized.set_text("미분류: -");
            let _ = items.status.set_text("상태: 확인 필요");
        }
    }
}

fn read_today_summary(app: &AppHandle) -> Result<(TodaySummaryDto, String), String> {
    let state = app.state::<AppState>();
    let repository = state
        .repository
        .lock()
        .map_err(|_| "Repository lock poisoned.".to_string())?;
    let summary = crate::commands::today_summary_from_repository(&repository)?;
    drop(repository);

    let status = state
        .tracking_status
        .lock()
        .map_err(|_| "Tracking status lock poisoned.".to_string())
        .map(|status| {
            if status.is_paused() {
                "일시정지".to_string()
            } else {
                "기록 중".to_string()
            }
        })?;

    Ok((summary, status))
}

fn start_tray_summary_refresh_loop(app: AppHandle, items: TraySummaryItems) {
    tauri::async_runtime::spawn_blocking(move || {
        loop {
            std::thread::sleep(std::time::Duration::from_secs(60));
            refresh_tray_summary(&app, &items);
        }
    });
}

fn build_summary_lines(summary: &TodaySummaryDto, status: &str) -> SummaryLines {
    SummaryLines {
        total: format!("오늘 기록: {}", format_duration_ko(summary.tracked_seconds)),
        productive: format!(
            "생산적: {}",
            format_duration_ko(summary.productive_seconds)
        ),
        unproductive: format!(
            "비생산: {}",
            format_duration_ko(summary.unproductive_seconds)
        ),
        neutral: format!("중립: {}", format_duration_ko(summary.neutral_seconds)),
        uncategorized: format!(
            "미분류: {}",
            format_duration_ko(summary.uncategorized_seconds)
        ),
        status: format!("상태: {status}"),
    }
}

fn format_duration_ko(seconds: i64) -> String {
    let minutes = if seconds <= 0 { 0 } else { (seconds + 59) / 60 };
    let hours = minutes / 60;
    let remaining_minutes = minutes % 60;

    match (hours, remaining_minutes) {
        (0, minutes) => format!("{minutes}분"),
        (hours, 0) => format!("{hours}시간"),
        (hours, minutes) => format!("{hours}시간 {minutes}분"),
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::TodaySummaryDto;

    #[test]
    fn formats_duration_for_menu_bar_summary() {
        assert_eq!(format_duration_ko(0), "0분");
        assert_eq!(format_duration_ko(59), "1분");
        assert_eq!(format_duration_ko(60), "1분");
        assert_eq!(format_duration_ko(3_660), "1시간 1분");
    }

    #[test]
    fn builds_korean_menu_bar_summary_lines() {
        let summary = TodaySummaryDto {
            tracked_seconds: 7_200,
            productive_seconds: 3_600,
            unproductive_seconds: 1_800,
            neutral_seconds: 900,
            idle_seconds: 600,
            uncategorized_seconds: 300,
        };

        let lines = build_summary_lines(&summary, "기록 중");

        assert_eq!(lines.total, "오늘 기록: 2시간");
        assert_eq!(lines.productive, "생산적: 1시간");
        assert_eq!(lines.unproductive, "비생산: 30분");
        assert_eq!(lines.neutral, "중립: 15분");
        assert_eq!(lines.uncategorized, "미분류: 5분");
        assert_eq!(lines.status, "상태: 기록 중");
    }
}
