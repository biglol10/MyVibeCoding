# MyMacCalendar Calendar UI Redesign Spec

Date: 2026-06-25

Status: Historical redesign spec. It records the direction used for the UI pass, but the current implementation details live in `README.md` and the source tree.

## 1. Problem

The current main UI looks like a set of disconnected date cards rather than a professional calendar. The right-side panel dominates too much of the window, the month grid lacks real calendar structure, and the date cells do not provide enough room for actual event bars.

The redesign should follow the user's first reference image: a dark, full-window monthly grid with clear hierarchy, thin cell boundaries, large Korean month title, compact top-right navigation, and event pills inside each date cell.

## 2. Goals

- Make the monthly calendar the primary interface.
- Remove the always-visible right agenda panel from the main window.
- Render a fixed 7-column by 6-row month grid that fills the available window.
- Show holidays and user events as horizontal pills inside date cells.
- Keep event creation, editing, deletion, reminders, holidays, settings, and floating widget behavior intact.
- Make the UI feel native and professional on macOS dark mode.

## 3. Non-goals

- No account login, cloud sync, collaboration, or Apple Calendar sync.
- No timed event timeline view.
- No advanced recurring-event exceptions.
- No decorative landing page, marketing screen, or dashboard-first layout.

## 4. Main Window Layout

The main window becomes a single-surface monthly calendar.

Top bar:

- Large left-aligned title such as `2026년 6월`.
- Right-aligned compact controls: previous month, today, next month, quick add, new event, settings.
- Search should not occupy permanent horizontal space in v1 of the redesign. It can remain available through a toolbar item or future command surface.

Calendar body:

- Weekday header uses Korean weekday labels: `일`, `월`, `화`, `수`, `목`, `금`, `토`.
- Month grid is always 7 columns by 6 rows.
- Date cells use thin dividers, not card backgrounds.
- The calendar fills the content area with minimal outer padding.
- The app defaults to a dark professional palette close to the reference image.

## 5. Date Cell Design

Each cell contains:

- Date number aligned to the top-right.
- Current-month days use high-contrast text.
- Adjacent-month days use muted text and reduced contrast.
- Sundays and holidays use red-tinted text.
- Saturdays use muted blue text.
- Today uses a red circular badge behind the date number.
- Selected date uses only a subtle cell background or border so it does not compete with today.

Cells should not use tall rounded vertical bars. Those are the main reason the current UI looks weak.

## 6. Event And Holiday Rendering

Events and holidays render as compact horizontal pills.

Holiday pill:

- Purple background.
- Small filled star icon at the leading edge.
- Holiday title in Korean when available.
- Hidden imported holidays must not render.

User event pill:

- Uses the event's stored color.
- Title is single-line and truncated cleanly.
- Multi-day all-day events may render on each included day in v1. Spanning bars can be added later.

Overflow:

- Show up to three visible pills per cell, depending on cell height.
- If more items exist, show a compact `+N` overflow label.

## 7. Interaction Model

- Single-click a date cell: select that date.
- Double-click a date cell: open the event editor for a new all-day event on that date.
- Click an event pill: open the event editor for that event.
- Toolbar `+`: open the event editor for the selected date.
- Toolbar quick-add: open the quick add sheet.
- Toolbar settings: open the macOS settings scene.

The previous right agenda panel is removed from the default layout. If selected-day details are needed later, they should appear as a lightweight popover, inspector, or optional drawer rather than a permanent panel.

## 8. Settings, Editor, And Widget Polish

The main redesign focuses on the calendar, but the surrounding UI should stop feeling unfinished:

- Event editor should use clearer section grouping and stronger title hierarchy.
- Quick add should show a more polished preview state.
- Settings should keep the existing tabs but align labels, controls, and holiday rows more cleanly.
- Floating widget should preserve its current behavior while adopting the same dark, restrained visual language.

These supporting changes should remain scoped. The month view is the priority.

## 9. Accessibility And Resizing

- Month cells must keep stable proportions at the default window size.
- Text must not overflow controls or pills.
- Event pills must remain clickable at the default window size.
- The layout should degrade gracefully when the window narrows by reducing pill count before breaking the grid.
- Colors must preserve readable contrast in dark mode.

## 10. Implementation Boundaries

Likely files to modify:

- `Sources/MyMacCalendar/Views/MainWindowView.swift`
- `Sources/MyMacCalendar/Views/MonthGridView.swift`
- `Sources/MyMacCalendar/Views/EventEditorView.swift`
- `Sources/MyMacCalendar/Views/QuickAddView.swift`
- `Sources/MyMacCalendar/Views/SettingsView.swift`
- `Sources/MyMacCalendar/Views/FloatingWidgetView.swift`

The redesign should avoid model changes unless a view-level helper needs to calculate event occurrences for a displayed day.

## 11. Verification

Implementation is complete only after:

- The app builds or the build blocker is clearly identified.
- The main window is visually checked at the default size.
- Date selection, new event, edit event, and delete event still work.
- Holiday hiding/deleting behavior still works.
- The generated UI no longer uses the old vertical rounded day-card design.
