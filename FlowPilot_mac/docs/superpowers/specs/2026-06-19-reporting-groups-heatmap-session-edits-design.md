# FlowPilot Reporting, Grouping, Heatmap, and Session Edits Design

## Scope

This design covers five requested features:

- Date-range reports: today, yesterday, this week, last week, last 30 days, and custom date ranges.
- Rule recommendations: surface frequently seen uncategorized apps/sites and suggest one-click classification.
- App/site grouping: combine related domains and apps under one display group, such as Notion or YouTube.
- Activity heatmap: show time by weekday and hour.
- Session edit notes: let a user adjust one session's category/display name and attach a memo.

These features should improve analysis quality without changing the raw activity collection model. Raw sessions remain immutable tracking evidence; user edits and grouping are stored as overlays.

## Product Behavior

The app adds a date-range selector to report pages. All summary cards, timelines, usage tables, trend charts, and heatmaps read from the selected range instead of only today. The default range is Today.

Rule recommendations appear in the review workflow. FlowPilot groups repeated uncategorized items by domain or app process, ranks them by total time and frequency, and offers actions for productive, unproductive, neutral, or excluded. Creating a recommendation still creates a normal editable rule.

App/site groups let users define a display name and attach multiple matchers: domain, app, title keyword, or URL pattern. Reports aggregate matching sessions under the group name, while classification rules still decide productivity category. Groups are for cleaner reporting, not for overriding category.

The activity heatmap displays seven weekdays by twenty-four hours. Each cell uses total measured time for intensity and can optionally tint by dominant category. Excluded sessions do not contribute.

Session edits open from timeline/table rows. A user can override category for that session, set a custom display name, and add a note. Overrides affect reporting immediately. A reset action removes the override and restores automatic classification/grouping.

## Data Model

Add `activity_groups`:

- `id`
- `name`
- `color`
- `created_at`
- `updated_at`

Add `activity_group_matchers`:

- `id`
- `group_id`
- `rule_type`
- `pattern`
- `priority`

Add `session_overrides`:

- `session_id`
- `category_override`
- `display_name_override`
- `note`
- `updated_at`

Raw `activity_sessions` are not rewritten. Report queries classify the raw session, apply session override, filter ignored/excluded sessions, then apply group display names.

## API Design

Add report APIs:

- `get_summary_for_range(start, end)`
- `get_sessions_for_range(start, end)`
- `get_heatmap_for_range(start, end)`

Add group APIs:

- `list_activity_groups`
- `create_activity_group`
- `update_activity_group`
- `delete_activity_group`

Add session override APIs:

- `get_session_override(session_id)`
- `upsert_session_override`
- `delete_session_override`

Existing today APIs can remain as wrappers around the range APIs for compatibility.

## UI Design

Navigation remains page-based. The Today page becomes a report dashboard with a range selector at the top. Timeline and Weekly pages also receive the same range selector, but the selected range is shared app state so users do not have to reselect it on every page.

Recommended additions:

- Report header: range selector, refresh button, export button.
- Heatmap panel: compact grid with tooltip for hour, total time, and dominant category.
- Groups page section inside rule settings: group name, color, matchers, edit/delete.
- Review recommendations: ranked cards or table rows with quick classification buttons.
- Session edit drawer/modal: category selector, display name, note, reset action.

## Error Handling

Invalid date ranges are rejected in the frontend and backend. The backend clamps excessively large ranges to a configurable maximum, initially 180 days, to avoid heavy queries.

If a session override points to a deleted or missing session, it is ignored in reports. If a group matcher is invalid or blank, creation/update fails with a clear Korean error message.

## Testing

Backend tests cover:

- Range boundaries and local-day conversion.
- Ignored sessions excluded after overrides and grouping.
- Group matcher aggregation.
- Session override category/display name/note behavior.
- Heatmap bucket calculation by weekday and hour.

Frontend tests cover:

- Range selector changes report API calls.
- Recommended rules are ranked and create normal rules.
- Grouped sessions appear under the group name.
- Heatmap renders correct cells and empty state.
- Session edit saves, resets, and updates visible reports.

E2E tests cover one happy path: select a range, create a recommendation rule, group an app/site, edit a session note, and verify the report updates.

## Implementation Order

1. Add range report backend APIs and frontend range selector.
2. Add session override storage and edit UI.
3. Add activity groups and grouped report display.
4. Upgrade review recommendations.
5. Add heatmap panel.
6. Rebuild Windows installer and portable package with the existing packaging script.
