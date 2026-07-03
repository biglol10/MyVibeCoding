# MyMacCalendar Design Spec

Date: 2026-06-25

Status: Historical product/design baseline. The current implementation has evolved since this document was written; use `README.md` and the source tree as the current behavior reference.

## 1. Overview

MyMacCalendar is a local-first macOS calendar app for managing all-day events with a professional, information-dense UI.

The product is a standalone app, not a sync client for Apple Calendar or any other external calendar service.

The initial layout is a working hypothesis: a monthly calendar on the left/center and a right-side agenda panel. If the first real UI render feels weak in density, readability, or balance, the layout may change.

## 2. Goals

- Create, edit, search, and delete all-day events quickly.
- Support simple repeating events: weekly, monthly, yearly.
- Show a small floating upcoming-events widget even after the main window is closed.
- Use macOS notifications for event reminders.
- Store data locally on the Mac.
- Keep holiday data editable by the user, including hiding bad imported holiday rows.
- Present a professional macOS-native UI, not a playful or decorative one.

## 3. Non-goals

- Apple Calendar sync.
- Accounts, sign-in, or cloud sync.
- Timed events.
- Event attendees, invitations, files, locations, or shared calendars.
- Advanced recurrence exceptions such as "delete only this instance".
- Cross-device collaboration.

## 4. Supported Platform

- macOS 14 Sonoma or later.
- SwiftUI app with SwiftData for persistence.
- UserNotifications for reminders.
- AppKit only where SwiftUI needs help with the floating always-on-top window.

## 5. UX Surfaces

### 5.1 Main Window

- Monthly calendar view.
- Right-side agenda panel.
- Today/previous/next month navigation.
- Search.
- Quick add.
- New event.

The agenda panel shows the selected day plus upcoming events.

### 5.2 Quick Add

- Fast entry for all-day events.
- Accepts common numeric and Korean date phrases.
- If the parser is uncertain, show a confirmation step instead of saving silently.

### 5.3 Event Detail

- View, edit, and delete events.
- Delete requires confirmation.
- Period events delete the whole range.
- Repeating events delete the whole series in the first version.

### 5.4 Settings Window

Tabs:

- General
- Floating Widget
- Notifications
- Holidays
- Appearance
- Data

### 5.5 Menu Bar

- Open main window.
- Show or hide the floating widget.
- Open quick add.
- Open settings.

### 5.6 Floating Widget

- Small always-on-top upcoming-events box.
- Remains visible after the main window is closed, as long as the app is still running.
- Drag to reposition.
- Can be enabled or disabled from settings.
- Highlights today's event with a different color.

## 6. Data Model

### 6.1 Event

- `id`
- `title`
- `startDate`
- `endDate`
- `allDay` = true
- `color`
- `notes`
- `recurrenceRule`
- `notificationOffsetsDays`
- `createdAt`
- `updatedAt`

### 6.2 RecurrenceRule

- `none`
- `weekly`
- `monthly`
- `yearly`

No recurrence exceptions in v1.

### 6.3 NotificationRule

- Reminder offsets are stored as day offsets relative to the event date.
- The actual send time uses a user setting for the default reminder time.
- Default reminder time is 09:00.

### 6.4 HolidayRecord

Holiday data is merged from an imported API feed and user edits.

Fields:

- `id`
- `date`
- `title`
- `source` (`api` or `manual`)
- `providerKey` for imported rows
- `isHidden`
- `year`
- `updatedAt`

Behavior:

- Imported API rows can be hidden by the user.
- Hidden API rows must stay hidden after refetch.
- Manual holiday rows are user-owned and remain unless the user deletes them.
- Manual rows override imported rows on the same date.

### 6.5 Settings

Major settings:

- `launchAtLogin` meaning Mac start auto-run
- `showMenuBar`
- `floatingWidgetEnabled`
- `floatingWidgetAlwaysOnTop`
- `floatingWidgetOpacity`
- `floatingWidgetVisibleCount`
- `defaultReminderTime`
- `theme`
- `calendarDensity`

## 7. Functional Behavior

### 7.1 Event Calendar

- Render a monthly grid.
- Mark holidays.
- Mark event days with dots or compact bars.
- Show selected date details in the agenda panel.
- Refresh holiday data when the current year changes.
- Past years are not fetched automatically.

### 7.2 Event Creation and Editing

- All-day events are the default input model.
- Period events are allowed as date ranges.
- Repeat options are limited to weekly, monthly, yearly.
- No per-instance repeat deletion in v1.
- Save must update the event, upcoming calculations, and notification schedule together.

### 7.3 Event Search

- Search by title, notes, and date.
- Open the matching event from results.

### 7.4 Quick Add Parsing

The parser must support common cases such as:

- `2026-06-30 codex 만료`
- `6/30 codex 만료`
- `다음주 월요일 병원`

If parsing is ambiguous, show a confirmation sheet instead of guessing.

### 7.5 Notifications

- Support multiple reminders per event, such as 7 days, 2 days, 1 day, and day-of.
- Rebuild reminders when an event changes.
- Cancel reminders when an event is deleted.
- Denied notification permission must not block event saving.

### 7.6 Floating Widget

- Show the next N upcoming events.
- Highlight today differently.
- Clicking an item opens the main window and selects the related date.
- Widget position, opacity, and visibility persist locally.

### 7.7 Holiday Management

- Use a keyless public holiday source as an imported feed.
- Fetch the current year on launch when needed and when the year changes.
- If the feed fails, keep the last cached holiday data.
- Users can add, edit, and delete holidays in the Holiday settings tab.
- If a user hides an imported holiday, refetch must not bring it back.
- Holiday rows show whether they are imported or manual.

## 8. Error Handling

- Holiday fetch failure falls back to cached data.
- Bad holiday rows from the feed are ignored, not fatal.
- Notification permission denial keeps the app usable.
- Parser ambiguity falls back to confirmation.
- Storage errors must surface a visible alert and avoid silent data loss.

## 9. Internal Structure

Suggested modules:

- `CalendarStore`: SwiftData-backed persistence.
- `EventService`: event CRUD, recurrence expansion, search, delete behavior.
- `HolidayService`: holiday fetch, merge, hide-state preservation, manual holiday CRUD.
- `NotificationService`: schedule and cancel reminders.
- `FloatingWidgetController`: always-on-top widget window management.
- `QuickAddParser`: input parsing and ambiguity detection.
- `SettingsStore`: user preferences.

## 10. Testing

Unit tests must cover:

- monthly grid date logic
- recurrence expansion
- upcoming sort order
- quick add parsing
- notification date calculation
- holiday merge and hidden-row preservation
- delete behavior for normal and repeating events

UI checks must cover:

- main window layout
- settings tabs
- widget visibility and highlight behavior
- delete and quick-add flows

## 11. Acceptance Criteria

- User can create, edit, search, and delete all-day events.
- User can create weekly, monthly, and yearly repeating events.
- User can hide a bad imported holiday and it stays hidden after refetch.
- User can add manual holidays.
- The floating widget remains visible after closing the main window.
- Notifications use the configured default reminder time.
- The app runs locally on macOS 14+ without any account sign-in.
