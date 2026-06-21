# Reporting, Groups, Heatmap, and Session Edits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add date-range reports, rule recommendations, app/site grouping, an activity heatmap, and session edit notes while keeping the UI polished and readable.

**Architecture:** Treat raw sessions as immutable and build a report overlay pipeline: raw session -> classification -> session override -> ignored filter -> group display name -> report aggregates. The frontend shares one selected report range across pages and uses focused panels for range selection, heatmap, grouping, recommendations, and session editing.

**Tech Stack:** Tauri 2, Rust, rusqlite, React 19, TypeScript, Recharts, Vitest, Playwright.

---

## File Structure

- Modify `src-tauri/src/storage/schema.rs`: add `activity_groups`, `activity_group_matchers`, and `session_overrides`.
- Modify `src-tauri/src/storage/repository.rs`: add storage methods for groups, matchers, overrides, and range queries.
- Modify `src-tauri/src/commands.rs`: add report range commands, heatmap command, group commands, and override commands.
- Modify `src-tauri/src/lib.rs`: register new Tauri commands.
- Modify `src/types/activity.ts`: add range, group, matcher, override, heatmap, and extended session types.
- Modify `src/api/activityApi.ts`: add desktop command wrappers and dev fallback storage.
- Create `src/lib/reportRanges.ts`: date range presets and labels.
- Create `src/components/reports/ReportRangePicker.tsx`: compact range selector for report pages.
- Create `src/components/dashboard/ActivityHeatmap.tsx`: weekday/hour heatmap.
- Create `src/components/sessions/SessionEditModal.tsx`: session override editor.
- Create `src/components/groups/ActivityGroupsSettings.tsx`: group CRUD UI inside rules page.
- Modify `src/App.tsx`: hold selected range, load range reports, and pass edit/group callbacks.
- Modify report pages and table/timeline components to support grouped display names and session editing.
- Modify tests in `src/**/*.test.tsx`, `src/api/activityApi.test.ts`, and Rust repository/commands tests.

## UI/UX Guardrails

- Keep the top report control as a slim toolbar, not a large card.
- Avoid stuffing all features into one page; keep range selection global, heatmap in the report area, groups in settings, and session editing in a modal.
- Use Korean user-facing text.
- Use compact segmented controls for common date presets and date inputs only for custom mode.
- Preserve table scanability: action buttons should be short, aligned, and visually quieter than primary report content.
- Do not show ignored/excluded sessions in report aggregates.

---

### Task 1: Add Report Range Types and Utilities

**Files:**
- Modify: `src/types/activity.ts`
- Create: `src/lib/reportRanges.ts`
- Test: `src/lib/reportRanges.test.ts`

- [ ] **Step 1: Write the failing report range tests**

Create `src/lib/reportRanges.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { buildRangeFromPreset, RANGE_PRESETS } from "./reportRanges";

describe("reportRanges", () => {
  it("builds today and yesterday as local day ranges", () => {
    vi.setSystemTime(new Date("2026-06-19T10:30:00+09:00"));

    expect(buildRangeFromPreset("today")).toMatchObject({
      label: "오늘",
      start: "2026-06-18T15:00:00.000Z",
      end: "2026-06-19T15:00:00.000Z",
    });
    expect(buildRangeFromPreset("yesterday")).toMatchObject({
      label: "어제",
      start: "2026-06-17T15:00:00.000Z",
      end: "2026-06-18T15:00:00.000Z",
    });
  });

  it("ships a compact preset set for the report toolbar", () => {
    expect(RANGE_PRESETS.map((preset) => preset.id)).toEqual([
      "today",
      "yesterday",
      "thisWeek",
      "lastWeek",
      "last30Days",
      "custom",
    ]);
  });
});
```

- [ ] **Step 2: Run the range tests and verify RED**

Run: `npm test -- src/lib/reportRanges.test.ts`

Expected: FAIL because `src/lib/reportRanges.ts` does not exist.

- [ ] **Step 3: Add shared range types**

Append to `src/types/activity.ts`:

```ts
export type ReportRangePreset = "today" | "yesterday" | "thisWeek" | "lastWeek" | "last30Days" | "custom";

export interface ReportRange {
  end: string;
  label: string;
  preset: ReportRangePreset;
  start: string;
}
```

- [ ] **Step 4: Implement range helpers**

Create `src/lib/reportRanges.ts`:

```ts
import type { ReportRange, ReportRangePreset } from "../types/activity";

export const RANGE_PRESETS: Array<{ id: ReportRangePreset; label: string }> = [
  { id: "today", label: "오늘" },
  { id: "yesterday", label: "어제" },
  { id: "thisWeek", label: "이번 주" },
  { id: "lastWeek", label: "지난 주" },
  { id: "last30Days", label: "최근 30일" },
  { id: "custom", label: "직접 선택" },
];

const LABELS: Record<ReportRangePreset, string> = Object.fromEntries(
  RANGE_PRESETS.map((preset) => [preset.id, preset.label]),
) as Record<ReportRangePreset, string>;

function startOfLocalDay(date: Date): Date {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

function addDays(date: Date, days: number): Date {
  const copy = new Date(date);
  copy.setDate(copy.getDate() + days);
  return copy;
}

function startOfLocalWeek(date: Date): Date {
  const start = startOfLocalDay(date);
  const mondayOffset = (start.getDay() + 6) % 7;
  return addDays(start, -mondayOffset);
}

export function buildRangeFromPreset(preset: Exclude<ReportRangePreset, "custom">, now = new Date()): ReportRange {
  const today = startOfLocalDay(now);
  let start = today;
  let end = addDays(today, 1);

  if (preset === "yesterday") {
    start = addDays(today, -1);
    end = today;
  } else if (preset === "thisWeek") {
    start = startOfLocalWeek(today);
    end = addDays(start, 7);
  } else if (preset === "lastWeek") {
    end = startOfLocalWeek(today);
    start = addDays(end, -7);
  } else if (preset === "last30Days") {
    start = addDays(today, -29);
    end = addDays(today, 1);
  }

  return {
    preset,
    label: LABELS[preset],
    start: start.toISOString(),
    end: end.toISOString(),
  };
}

export function buildCustomRange(startDate: string, endDate: string): ReportRange {
  const start = startOfLocalDay(new Date(`${startDate}T00:00:00`));
  const end = addDays(startOfLocalDay(new Date(`${endDate}T00:00:00`)), 1);

  return {
    preset: "custom",
    label: `${startDate} - ${endDate}`,
    start: start.toISOString(),
    end: end.toISOString(),
  };
}
```

- [ ] **Step 5: Verify GREEN**

Run: `npm test -- src/lib/reportRanges.test.ts`

Expected: PASS.

---

### Task 2: Add Backend Overlay Storage

**Files:**
- Modify: `src-tauri/src/storage/schema.rs`
- Modify: `src-tauri/src/storage/repository.rs`

- [ ] **Step 1: Write failing schema tests**

Add to `src-tauri/src/storage/schema.rs` tests:

```rust
#[test]
fn creates_report_overlay_tables() {
    let conn = Connection::open_in_memory().expect("in-memory db");
    initialize_schema(&conn).expect("schema initialized");

    for table_name in [
        "activity_groups",
        "activity_group_matchers",
        "session_overrides",
    ] {
        let exists: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?1",
                [table_name],
                |row| row.get(0),
            )
            .expect("table count");

        assert_eq!(exists, 1, "{table_name} should exist");
    }
}
```

- [ ] **Step 2: Run schema test and verify RED**

Run: `cargo test storage::schema::tests::creates_report_overlay_tables --target x86_64-pc-windows-gnu`

Expected: FAIL because the tables do not exist.

- [ ] **Step 3: Add schema**

Add to `initialize_schema` after `classification_results`:

```sql
CREATE TABLE IF NOT EXISTS activity_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS activity_group_matchers (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  rule_type TEXT NOT NULL,
  pattern TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(group_id) REFERENCES activity_groups(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS session_overrides (
  session_id TEXT PRIMARY KEY,
  category_override TEXT,
  display_name_override TEXT,
  note TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_group_matchers_group_id ON activity_group_matchers(group_id);
```

- [ ] **Step 4: Add repository structs and methods**

Add Rust structs:

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivityGroup {
    pub id: String,
    pub name: String,
    pub color: String,
    pub matchers: Vec<ActivityGroupMatcher>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivityGroupMatcher {
    pub id: String,
    pub group_id: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub priority: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionOverride {
    pub session_id: String,
    pub category_override: Option<ProductivityCategory>,
    pub display_name_override: Option<String>,
    pub note: Option<String>,
}
```

Add methods: `save_group`, `list_groups`, `delete_group`, `upsert_session_override`, `get_session_override`, `delete_session_override`, `list_overrides_between`. Use the existing `rule_type_to_db`, `rule_type_from_db`, `productivity_category_to_db`, and `productivity_category_from_db` helpers.

- [ ] **Step 5: Verify backend storage**

Run: `cargo test storage::schema::tests::creates_report_overlay_tables --target x86_64-pc-windows-gnu`

Expected: PASS.

---

### Task 3: Add Range Report, Heatmap, Group, and Override Commands

**Files:**
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write failing command tests**

Add command tests that save sessions across two days, add one session override, add one group matcher, then assert:

```rust
assert_eq!(summary.tracked_seconds, 900);
assert_eq!(sessions[0].display_name.as_deref(), Some("Notion"));
assert_eq!(sessions[0].note.as_deref(), Some("회의 준비"));
assert_eq!(heatmap.iter().map(|bucket| bucket.seconds).sum::<i64>(), 900);
```

- [ ] **Step 2: Run command tests and verify RED**

Run: `cargo test commands::tests::range_reports_apply_overrides_groups_and_heatmap --target x86_64-pc-windows-gnu`

Expected: FAIL because commands and DTO fields do not exist.

- [ ] **Step 3: Extend DTOs**

Add fields to `ActivitySessionDto`:

```rust
pub display_name: String,
pub note: Option<String>,
pub category_source: String,
```

Add DTOs:

```rust
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HeatmapBucketDto {
    pub weekday: u32,
    pub hour: u32,
    pub seconds: i64,
    pub dominant_category: ProductivityCategory,
}
```

- [ ] **Step 4: Implement command pipeline**

Create helper:

```rust
fn classified_sessions_for_range(repository: &Repository, start: DateTime<Utc>, end: DateTime<Utc>) -> Result<Vec<ActivitySessionDto>, String>
```

Update this helper so it:

1. Loads raw sessions between range.
2. Classifies each session.
3. Applies session override category/name/note.
4. Drops `ProductivityCategory::Ignored`.
5. Applies first matching activity group display name.
6. Returns sessions sorted by start.

- [ ] **Step 5: Add public commands**

Add:

```rust
#[tauri::command]
pub fn get_summary_for_range(state: State<AppState>, start: String, end: String) -> Result<TodaySummaryDto, String>

#[tauri::command]
pub fn get_sessions_for_range(state: State<AppState>, start: String, end: String) -> Result<Vec<ActivitySessionDto>, String>

#[tauri::command]
pub fn get_heatmap_for_range(state: State<AppState>, start: String, end: String) -> Result<Vec<HeatmapBucketDto>, String>
```

Keep `get_today_summary` and `get_today_sessions` as wrappers.

- [ ] **Step 6: Register commands**

Add new commands to `src-tauri/src/lib.rs` `tauri::generate_handler!`.

- [ ] **Step 7: Verify command tests**

Run: `cargo test commands::tests::range_reports_apply_overrides_groups_and_heatmap --target x86_64-pc-windows-gnu`

Expected: PASS.

---

### Task 4: Add Frontend API Types and Dev Fallback

**Files:**
- Modify: `src/types/activity.ts`
- Modify: `src/api/activityApi.ts`
- Test: `src/api/activityApi.test.ts`

- [ ] **Step 1: Write failing frontend API tests**

Add tests:

```ts
it("returns report data for a selected range", async () => {
  const range = buildRangeFromPreset("today");
  await expect(getSummaryForRange(range)).resolves.toMatchObject({ trackedSeconds: expect.any(Number) });
  await expect(getSessionsForRange(range)).resolves.toEqual(expect.any(Array));
});

it("applies session overrides and groups in dev fallback", async () => {
  await upsertSessionOverride({ sessionId: "dev-3", categoryOverride: "productive", displayNameOverride: "개발 작업", note: "집중 코딩" });
  await createActivityGroup({ name: "AI 도구", color: "#2563eb", matchers: [{ ruleType: "domain", pattern: "chatgpt.com" }] });
  const sessions = await getSessionsForRange(buildRangeFromPreset("today"));
  expect(sessions.some((session) => session.displayName === "AI 도구")).toBe(true);
  expect(sessions.some((session) => session.note === "집중 코딩")).toBe(true);
});
```

- [ ] **Step 2: Run API tests and verify RED**

Run: `npm test -- src/api/activityApi.test.ts`

Expected: FAIL because functions and types do not exist.

- [ ] **Step 3: Add TypeScript types**

Add:

```ts
export interface ReportActivitySession extends ActivitySession {
  categorySource: "automatic" | "override";
  displayName: string;
  note?: string | null;
}

export interface HeatmapBucket {
  dominantCategory: ProductivityCategory;
  hour: number;
  seconds: number;
  weekday: number;
}

export interface ActivityGroupMatcherDraft {
  pattern: string;
  ruleType: RuleType;
}

export interface ActivityGroup {
  color: string;
  id: string;
  matchers: Array<ActivityGroupMatcherDraft & { id: string }>;
  name: string;
}

export interface ActivityGroupDraft {
  color: string;
  matchers: ActivityGroupMatcherDraft[];
  name: string;
}

export interface SessionOverrideDraft {
  categoryOverride?: ProductivityCategory | null;
  displayNameOverride?: string | null;
  note?: string | null;
  sessionId: string;
}
```

- [ ] **Step 4: Add API wrappers**

Export:

```ts
getSummaryForRange(range)
getSessionsForRange(range)
getHeatmapForRange(range)
listActivityGroups()
createActivityGroup(draft)
updateActivityGroup(id, draft)
deleteActivityGroup(id)
upsertSessionOverride(draft)
deleteSessionOverride(sessionId)
```

The dev fallback keeps `devGroups` and `devSessionOverrides` arrays in memory.

- [ ] **Step 5: Verify API tests**

Run: `npm test -- src/api/activityApi.test.ts`

Expected: PASS.

---

### Task 5: Add Shared Report Range Toolbar

**Files:**
- Create: `src/components/reports/ReportRangePicker.tsx`
- Modify: `src/App.tsx`
- Modify: `src/App.test.tsx`
- Modify: `src/styles.css`

- [ ] **Step 1: Write failing App test**

Add:

```ts
it("reloads report data when the range preset changes", async () => {
  render(<App />);
  await screen.findByRole("heading", { name: "핵심 지표" });
  await userEvent.click(screen.getByRole("button", { name: "어제" }));
  await waitFor(() => expect(getSummaryForRange).toHaveBeenCalledTimes(2));
});
```

- [ ] **Step 2: Run App test and verify RED**

Run: `npm test -- src/App.test.tsx`

Expected: FAIL because range controls do not exist.

- [ ] **Step 3: Implement ReportRangePicker**

Create a toolbar with segmented preset buttons. For custom mode, reveal two date inputs and an apply button. Use labels: `오늘`, `어제`, `이번 주`, `지난 주`, `최근 30일`, `직접 선택`.

- [ ] **Step 4: Wire App state**

Replace `getTodaySummary/getTodaySessions` calls with `getSummaryForRange/getSessionsForRange`. Store `reportRange` in `App`, render `ReportRangePicker` in the page header, and reload when range changes.

- [ ] **Step 5: Style the toolbar**

Add CSS classes:

```css
.report-toolbar { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.range-segment { min-height: 34px; padding: 6px 10px; border-radius: 6px; }
.range-segment[aria-pressed="true"] { background: #172033; color: #ffffff; }
.custom-range-fields { display: flex; align-items: center; gap: 8px; }
```

- [ ] **Step 6: Verify App test**

Run: `npm test -- src/App.test.tsx`

Expected: PASS.

---

### Task 6: Add Session Edit Modal

**Files:**
- Create: `src/components/sessions/SessionEditModal.tsx`
- Modify: `src/components/tables/UsageTable.tsx`
- Modify: `src/components/dashboard/DayTimeline.tsx`
- Modify: `src/App.tsx`
- Test: `src/components/sessions/SessionEditModal.test.tsx`

- [ ] **Step 1: Write failing modal test**

Create test:

```ts
it("saves a category, display name, and note override", async () => {
  const onSave = vi.fn();
  render(<SessionEditModal session={session} onClose={vi.fn()} onSave={onSave} onReset={vi.fn()} />);
  await userEvent.selectOptions(screen.getByLabelText("분류"), "productive");
  await userEvent.clear(screen.getByLabelText("표시 이름"));
  await userEvent.type(screen.getByLabelText("표시 이름"), "회의 준비");
  await userEvent.type(screen.getByLabelText("메모"), "강의 영상");
  await userEvent.click(screen.getByRole("button", { name: "저장" }));
  expect(onSave).toHaveBeenCalledWith(expect.objectContaining({ displayNameOverride: "회의 준비", note: "강의 영상" }));
});
```

- [ ] **Step 2: Run modal test and verify RED**

Run: `npm test -- src/components/sessions/SessionEditModal.test.tsx`

Expected: FAIL because modal does not exist.

- [ ] **Step 3: Implement modal**

Use a centered modal with title `세션 수정`, category select, display name input, memo textarea, `저장`, `초기화`, `닫기`.

- [ ] **Step 4: Add edit affordances**

Add a quiet `수정` button in `UsageTable` rows and make timeline segments keyboard focusable with an edit callback. Keep row density compact.

- [ ] **Step 5: Wire save/reset to App**

`App` stores `editingSession`. On save, call `upsertSessionOverride`, close modal, and reload current report range. On reset, call `deleteSessionOverride`, close modal, and reload.

- [ ] **Step 6: Verify modal flow**

Run: `npm test -- src/components/sessions/SessionEditModal.test.tsx src/App.test.tsx`

Expected: PASS.

---

### Task 7: Add Activity Groups Settings and Grouped Report Display

**Files:**
- Create: `src/components/groups/ActivityGroupsSettings.tsx`
- Modify: `src/components/rules/RulesSettings.tsx`
- Modify: `src/components/tables/UsageTable.tsx`
- Test: `src/components/groups/ActivityGroupsSettings.test.tsx`

- [ ] **Step 1: Write failing group settings test**

Create test:

```ts
it("creates an app/site group with multiple matchers", async () => {
  const onChanged = vi.fn();
  render(<ActivityGroupsSettings onChanged={onChanged} />);
  await userEvent.type(screen.getByLabelText("그룹 이름"), "YouTube");
  await userEvent.type(screen.getByLabelText("패턴"), "youtube.com");
  await userEvent.click(screen.getByRole("button", { name: "그룹 추가" }));
  expect(await screen.findByText("YouTube")).toBeInTheDocument();
  expect(onChanged).toHaveBeenCalled();
});
```

- [ ] **Step 2: Run group test and verify RED**

Run: `npm test -- src/components/groups/ActivityGroupsSettings.test.tsx`

Expected: FAIL because group settings do not exist.

- [ ] **Step 3: Implement group settings panel**

Add a panel below the rules table with inputs for group name, color, rule type, and pattern. Render existing groups in a compact table.

- [ ] **Step 4: Use display names in reports**

Ensure `UsageTable`, `TodaySummary`, and timeline use `session.displayName` when available, falling back to `domain ?? appName`.

- [ ] **Step 5: Verify grouped display**

Run: `npm test -- src/components/groups/ActivityGroupsSettings.test.tsx src/components/tables/UsageTable.test.tsx src/components/dashboard/TodaySummary.test.tsx`

Expected: PASS.

---

### Task 8: Upgrade Rule Recommendations

**Files:**
- Modify: `src/components/rules/UncategorizedReview.tsx`
- Modify: `src/components/rules/UncategorizedReview.test.tsx`

- [ ] **Step 1: Write failing recommendation ranking test**

Add:

```ts
it("ranks recommendations by time and session count", () => {
  render(<UncategorizedReview sessions={[shortSession, longSession, longSession2]} onRuleCreated={vi.fn()} />);
  const rows = screen.getAllByRole("row");
  expect(rows[1]).toHaveTextContent("long.example");
});
```

- [ ] **Step 2: Run review tests and verify RED**

Run: `npm test -- src/components/rules/UncategorizedReview.test.tsx`

Expected: FAIL if rows are not sorted by impact.

- [ ] **Step 3: Improve recommendation UI**

Sort by `durationSeconds DESC`, then `count DESC`, then `name ASC`. Rename heading to `추천 규칙`. Add a small explanation line: `자주 보이는 미분류 항목을 규칙으로 정리하세요.`

- [ ] **Step 4: Verify review tests**

Run: `npm test -- src/components/rules/UncategorizedReview.test.tsx`

Expected: PASS.

---

### Task 9: Add Activity Heatmap

**Files:**
- Create: `src/components/dashboard/ActivityHeatmap.tsx`
- Modify: `src/pages/WeeklyReportPage.tsx`
- Test: `src/components/dashboard/ActivityHeatmap.test.tsx`

- [ ] **Step 1: Write failing heatmap test**

Create:

```ts
it("renders weekday and hour cells with accessible labels", () => {
  render(<ActivityHeatmap buckets={[{ weekday: 1, hour: 9, seconds: 1800, dominantCategory: "productive" }]} />);
  expect(screen.getByLabelText("월요일 9시, 30분, 생산적")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run heatmap test and verify RED**

Run: `npm test -- src/components/dashboard/ActivityHeatmap.test.tsx`

Expected: FAIL because heatmap does not exist.

- [ ] **Step 3: Implement heatmap panel**

Render a 7 x 24 CSS grid. Use weekday labels down the left and hours across the top. Cell opacity is based on the maximum bucket seconds. Use category color as tint.

- [ ] **Step 4: Add heatmap to weekly report**

Pass heatmap buckets from `App` to `WeeklyReportPage` and render `ActivityHeatmap` above the table.

- [ ] **Step 5: Verify heatmap tests**

Run: `npm test -- src/components/dashboard/ActivityHeatmap.test.tsx src/App.test.tsx`

Expected: PASS.

---

### Task 10: Final Verification and Packaging

**Files:**
- Existing package script: `scripts/package-windows-dist.ps1`

- [ ] **Step 1: Run full frontend tests**

Run: `npm test`

Expected: all test files pass.

- [ ] **Step 2: Run production build**

Run: `npm run build`

Expected: TypeScript and Vite build pass.

- [ ] **Step 3: Run E2E tests**

Run: `npm run e2e`

Expected: desktop and mobile dashboard tests pass.

- [ ] **Step 4: Run Rust tests from ASCII build folder**

Run from `C:\tm-windows-mvp\src-tauri`:

```powershell
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:CARGO_BUILD_JOBS = '1'
cargo test --target x86_64-pc-windows-gnu
```

Expected: all Rust tests pass.

- [ ] **Step 5: Build Windows installer**

Run from `C:\tm-windows-mvp`:

```powershell
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-gnu'
$env:CARGO_BUILD_JOBS = '1'
npx tauri build --target x86_64-pc-windows-gnu --bundles nsis
powershell -ExecutionPolicy Bypass -File scripts\package-windows-dist.ps1
```

Expected: `FlowPilot_0.1.0_x64-setup.exe`, `flowpilot.exe`, `WebView2Loader.dll`, and `FlowPilot-0.1.0-portable.zip` exist.

- [ ] **Step 6: Smoke test installer and portable package**

Install NSIS silently to `C:\tm-windows-mvp\installer-smoke-test`, run `flowpilot.exe`, verify the process remains alive for 5 seconds, then uninstall. Extract portable zip to `C:\tm-windows-mvp\portable-smoke-test`, run `FlowPilot.exe`, verify it remains alive for 5 seconds, then stop it.

Expected: both launch without `WebView2Loader.dll` errors.

---

## Self-Review Notes

- Spec coverage: date ranges are covered by Tasks 1, 3, 4, and 5; rule recommendations by Task 8; grouping by Tasks 2, 3, 4, and 7; heatmap by Tasks 3, 4, and 9; session edits by Tasks 2, 3, 4, and 6.
- Completeness scan: no incomplete markers are intentionally left in this plan.
- Type consistency: report range, heatmap, group, matcher, and session override names match across planned Rust and TypeScript layers.
