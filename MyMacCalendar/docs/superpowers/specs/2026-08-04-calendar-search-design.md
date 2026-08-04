# Calendar Search UI Design

Date: 2026-08-04

## Goal

Expose the existing title/notes search logic as a compact, native-feeling macOS workflow without reducing the usable month grid or introducing a separate search window.

## User Experience

- Add a 220-point search field to the main header between the month title and navigation controls.
- Keep the month grid unchanged while searching so users retain date context.
- Replace the right selected-day panel with a search results panel when the trimmed query is non-empty.
- Show result count, title, anchor date, category, recurrence indicator, and a one-line notes excerpt when available.
- Clicking a result selects its start date, moves the visible month to that date, and opens the existing event editor.
- A clear icon returns immediately to the selected-day panel.
- `Command-F` focuses the search field. Escape first clears a non-empty query and otherwise releases focus.

## Architecture

- `MainWindowView` owns `searchQuery` and search focus because it already coordinates month selection and sheets.
- `CalendarSearchField` and `CalendarSearchResultsView` live in a focused view file and receive bindings/callbacks only.
- `EventService.search` remains the single matching implementation and returns deterministic date/title ordering for UI and non-UI callers.
- `AppCommandNotifications` carries the find command from the app scene to the active main window without introducing global mutable search state.

## Empty and Error States

- Whitespace-only input is treated as no search and keeps the day panel visible.
- No matches show a quiet `검색 결과 없음` state with no disabled or misleading actions.
- Search is local and synchronous; it does not add network or persistence failure paths.

## Accessibility and Layout

- The field uses a visible magnifying-glass symbol, a native text field, and an icon-only clear button with help text and accessibility label.
- Result rows are full-width buttons with title and metadata truncated within the fixed 280-point panel.
- Search controls have stable dimensions so text changes do not move the calendar navigation buttons.

## Verification

- Behavioral test: search trims input and sorts by start date then title.
- Source wiring test: field, result panel, clear action, result selection, and `Command-F` are connected.
- Full Swift test and release build.
- Isolated app smoke: title match, notes match, no-result state, clear, result click/date jump/editor, `Command-F`, Escape, and relaunch.
