# Professional Korean UI Redesign

Date: 2026-06-18
Status: Ready for user spec review

## Objective

Redesign the Windows MVP UI so it feels like a professional desktop time analytics product rather than a simple demo dashboard. The product should be dense enough for repeated daily use, colorful enough to make productivity state obvious, and fully localized into Korean for all visible informational text.

The approved direction is a hybrid:

- Use a ManicTime-like structure for the core product: navigation, timelines, tables, reports, and rule management.
- Use RescueTime-like color signals and summary cards on the first screen so the user can understand the day quickly.
- Use ActivityWatch-like local activity transparency: app/domain usage, categories, charts, and configurable rules remain visible and user-controllable.

## Product Principles

- Separate screens by job. Do not place every chart, table, rule form, and review queue on one scroll-heavy page.
- Keep the first screen useful at a glance. It should summarize the day, not expose every control.
- Prefer operational desktop UI over a marketing page. The app should feel like a work tool.
- Use Korean labels, status text, empty states, errors, button text, table headers, chart labels, and helper text.
- Keep domain names, product names, executable names, and URLs in their original form when they are actual data.
- Make default classifications broad but editable. The app should help immediately, while allowing the user to override rules later.

## Reference Notes

- ManicTime emphasizes timeline-centered time tracking and screenshot/timeline context. This supports a timeline-first professional structure.
- RescueTime emphasizes productivity summaries, focus/reporting, and clear productivity signals. This supports colorful scorecards and trend charts.
- ActivityWatch emphasizes local, app/website-based activity analysis and configurable categorization. This supports transparent local reporting and user-controlled classification.

Reference URLs:

- https://www.manictime.com/features/time-tracking-with-screenshots
- https://docs.manictime.com/win-client/plugins/timeline-plugins
- https://www.rescuetime.com/
- https://help.rescuetime.com/article/435-rescuetime-for-android-features
- https://activitywatch.net/
- https://activitywatch.net/screenshots/

## Information Architecture

Use a persistent left sidebar on desktop. On narrow widths, collapse the sidebar to icon-only or hide it behind a compact navigation control.

Primary screens:

- Today Summary: daily KPI cards, timeline preview, top usage table, weekly mini chart, and actionable alerts.
- Timeline: full-day activity timeline, session details, filters, and category correction controls.
- Weekly Report: day-by-day charts, category totals, app/domain tables, and export actions.
- Uncategorized Review: fast review queue for new domains, apps, and title keywords.
- Rules: category rules for domains, apps, and title keywords, including default presets and user overrides.

Optional later screens:

- Settings: tracking interval, idle threshold, data retention, startup behavior, and privacy controls.
- Exports: CSV/JSON export history if export behavior grows beyond a simple action.

## Screen Design

### Today Summary

Purpose: answer "How did today go?" without forcing the user to scroll through everything.

Layout:

- Top bar with current date, tracking status, and date range segmented control.
- Four KPI cards: total tracked time, productive time, unproductive time, review-needed count.
- Timeline preview with only the most important segments.
- Top usage table limited to the highest-impact apps/domains.
- Weekly mini chart and a short actionable queue on the right.

This screen should avoid full rule forms, long tables, and full timeline editing.

### Timeline

Purpose: inspect and correct the exact activity record.

Layout:

- Full-width timeline with category colors.
- Filters for category, source type, app/domain, and time range.
- Details table below or beside the timeline.
- Inline action to reclassify a selected segment.

This is the best place for heavier interaction because the user's intent is inspection.

### Weekly Report

Purpose: compare days and export useful reports.

Layout:

- Stacked daily bar chart by category.
- Category totals and productivity trend.
- App/domain ranking table.
- CSV export action.

This screen can be denser than Today Summary because it is a reporting workflow.

### Uncategorized Review

Purpose: reduce future manual cleanup.

Layout:

- Queue of new apps, domains, and title keywords.
- One-click category selection for productive, neutral, unproductive, ignored.
- "Create rule" flow that previews how many past/future records it will affect.

This screen should feel like an inbox triage tool.

### Rules

Purpose: let the user customize classifications later.

Layout:

- Separate tabs or segmented controls for domains, apps, and title keywords.
- Search/filter input.
- Rule table with pattern, category, source, priority, enabled state, and actions.
- Add/edit form in a side panel or modal, not permanently competing with the table.

Rules must clearly distinguish built-in presets from user-created overrides.

## Korean Localization

All visible information text should be Korean:

- Navigation labels
- Page titles
- KPI labels and descriptions
- Chart labels and legends
- Table headers
- Empty states
- Loading states
- Error messages
- Button text
- Form labels and placeholders
- Rule source/category/status text
- Test-facing accessible labels where they are visible to users

Accepted exceptions:

- Real domain names such as `youtube.com`, `chatgpt.com`, `naver.com`
- Product/app names such as `ChatGPT`, `Codex`, `Chrome`, `Visual Studio Code`
- File formats and technical export names such as `CSV`, `JSON`

Recommended category labels:

- 생산적
- 중립
- 비생산
- 제외
- 검토 필요

Recommended source labels:

- 기본 규칙
- 사용자 규칙
- 제목 키워드
- 앱
- 도메인

## Default Classification Presets

Defaults should be broad enough that the first run feels useful. They must remain editable by the user.

Productive defaults:

- AI and coding: ChatGPT, OpenAI, Codex, GitHub, Stack Overflow, developer documentation, IDEs, terminals.
- Documents and work tools: Google Docs, Google Drive, Notion, Microsoft Office, Slack or Discord only when used as work tools if the user later overrides them.
- Search and research can be neutral or productive depending on context; start broad search domains as neutral to avoid over-claiming productivity.

Neutral defaults:

- Google Search
- Naver
- Wikipedia
- Email
- Calendar
- General portals where intent depends on content

Unproductive defaults:

- YouTube
- Instagram
- TikTok
- X/Twitter
- Facebook
- Chzzk
- Twitch
- Netflix and other streaming services
- Shopping and entertainment-heavy communities

Ignored defaults:

- System shell/background utilities
- The time manager app itself, when appropriate

Uncategorized:

- Any new app/domain/title that does not match a preset or user rule.

## Visual System

The UI should use multiple semantic colors, not a single blue or gray palette.

Recommended color mapping:

- Productive: green
- Neutral: amber or slate
- Unproductive: red
- Uncategorized/review needed: purple
- Selected range or primary action: blue

Use restrained surfaces:

- Left sidebar: dark, compact, stable navigation.
- Main background: light gray.
- Panels/cards: white with subtle borders and 8px radius.
- Cards are for repeated metrics or panels, not nested decorative containers.
- Tables should be scan-friendly with clear row spacing and category badges.

## Components

Expected React components:

- `AppShell`: left navigation, responsive shell, tracking status.
- `TodaySummaryPage`: first-screen dashboard composition.
- `TimelinePage`: detailed timeline and segment review.
- `WeeklyReportPage`: charts, tables, export controls.
- `UncategorizedReviewPage`: review queue and quick rule creation.
- `RulesPage`: searchable rules table and add/edit flow.
- Shared components: `MetricCard`, `CategoryBadge`, `SegmentTimeline`, `UsageTable`, `ReportChart`, `EmptyState`, `ErrorState`, `DateRangeControl`.

Keep page components focused. Shared components should receive already-shaped view data and avoid owning storage logic.

## Data Flow

The existing collection, classification, and SQLite-backed storage model should remain intact.

UI data flow:

1. Tauri commands load sessions, rules, summaries, and review items.
2. Page-level components transform raw records into view models.
3. Shared visual components render those view models.
4. Rule edits and review actions call existing storage commands.
5. The UI refreshes affected summaries, tables, and review counts after mutations.

The redesign should not require changing the collector. It may require adding or reshaping frontend view models for cleaner page boundaries.

## Error Handling And Empty States

Loading states should be Korean and screen-specific:

- "오늘 기록을 불러오는 중입니다"
- "타임라인을 불러오는 중입니다"
- "분류 규칙을 불러오는 중입니다"

Error states should tell the user what failed and offer a retry action:

- "활동 데이터를 불러오지 못했습니다"
- "다시 시도"

Empty states should be useful:

- No activity: "아직 기록된 활동이 없습니다"
- No uncategorized items: "검토할 항목이 없습니다"
- No rules: "분류 규칙이 없습니다"

## Testing And Verification

Required checks after implementation:

- Unit/component tests updated from English expectations to Korean expectations.
- E2E test verifies navigation between Today Summary, Timeline, Weekly Report, Uncategorized Review, and Rules.
- E2E test verifies rule customization remains functional.
- E2E test verifies the add/edit rules UI does not overlap at narrow widths.
- Screenshot verification at desktop and narrow widths.
- Browser or native app screenshots reviewed for text overflow, cramped tables, and incoherent overlap.
- Basic smoke test for Tauri dev app if the local environment supports it.

## Out Of Scope For This Redesign

- Blocking websites or apps.
- Cloud sync.
- Team dashboards.
- Billing or attendance workflows.
- Screenshot recording.
- macOS collector implementation.
- A full i18n framework with runtime language switching.

The implementation can use direct Korean strings for this MVP. A formal i18n layer can be introduced later if the app needs multiple languages.

## Acceptance Criteria

- The first screen no longer tries to contain every workflow.
- The app has a professional sidebar-based structure.
- Core workflows are split into clear pages.
- Charts and tables remain visible and central to the product.
- All user-facing informational text is Korean.
- Default domain/app classifications include broad common services such as YouTube, Chzzk, Naver, Google, ChatGPT, Codex, Instagram, and developer tools.
- Users can still customize classification rules after the redesign.
- Desktop and narrow screenshots show no obvious text overlap or broken layout.
