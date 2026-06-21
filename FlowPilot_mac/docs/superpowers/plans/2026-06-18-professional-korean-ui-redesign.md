# Professional Korean UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the current single-page English dashboard into a professional Korean desktop analytics UI with sidebar navigation, separated workflows, colorful charts/tables, broad default classifications, and preserved rule customization.

**Architecture:** Keep the existing Tauri command and SQLite data flow intact. Refactor the React layer into an app shell plus page components, centralize Korean labels, reuse current chart/table/rule components behind clearer page boundaries, and update tests to assert Korean user-facing text. The redesign is frontend-heavy; backend collector changes are out of scope.

**Tech Stack:** React, TypeScript, Vite, Tauri command wrappers, Recharts, lucide-react, Vitest, React Testing Library, Playwright.

---

## Source Notes

- Approved design spec: `docs/superpowers/specs/2026-06-18-professional-korean-ui-redesign.md`
- Current app composition: `src/App.tsx`
- Current visual system: `src/styles.css`
- Current category colors and labels: `src/lib/colors.ts`
- Current dev fallback presets: `src/api/activityApi.ts`
- Current e2e smoke test: `tests/e2e/dashboard.spec.ts`

## File Structure

Create these files:

- `src/lib/labels.ts`: Korean UI labels for categories, rule types, rule sources, navigation, status, empty states, and screen copy.
- `src/lib/labels.test.ts`: tests proving the Korean label layer covers the visible categories and rule metadata.
- `src/types/navigation.ts`: typed page identifiers for sidebar navigation.
- `src/components/layout/AppShell.test.tsx`: tests for the Korean sidebar shell.
- `src/pages/TodayPage.tsx`: first-screen summary page.
- `src/pages/TimelinePage.tsx`: detailed timeline page.
- `src/pages/WeeklyReportPage.tsx`: report page with chart and table.
- `src/pages/ReviewPage.tsx`: uncategorized review page.
- `src/pages/RulesPage.tsx`: classification rules page.

Modify these files:

- `src/lib/colors.ts`: remove English category labels from this file and keep it focused on colors.
- `src/api/activityApi.ts`: broaden built-in dev fallback rules and sample data.
- `src/api/activityApi.test.ts`: assert broad default classifications and Korean-safe rule validation errors.
- `src/components/layout/AppShell.tsx`: replace top-only header with responsive sidebar shell.
- `src/App.tsx`: own page selection and render one workflow at a time.
- `src/App.test.tsx`: update expectations for Korean labels and page navigation.
- `src/components/dashboard/TodaySummary.tsx`: Koreanize labels and keep first-screen metrics focused.
- `src/components/dashboard/DayTimeline.tsx`: Koreanize heading, empty state, and accessible timeline text.
- `src/components/dashboard/WeeklyTrends.tsx`: Koreanize chart copy and tooltip labels.
- `src/components/tables/UsageTable.tsx`: add configurable title/description/limit and Korean table labels.
- `src/components/rules/RulesSettings.tsx`: Koreanize rule UI and make rule form/table fit a dedicated screen.
- `src/components/rules/UncategorizedReview.tsx`: Koreanize review queue and quick actions.
- Component tests under `src/components/**`: update English assertions to Korean.
- `src/styles.css`: implement dark sidebar, page layout, colorful metric/report surfaces, and responsive rules/review layout.
- `tests/e2e/dashboard.spec.ts`: verify Korean UI, page separation, sidebar navigation, and colorful cards.

## Task 1: Centralize Korean Labels And Broaden Defaults

**Files:**
- Create: `src/lib/labels.ts`
- Create: `src/lib/labels.test.ts`
- Modify: `src/lib/colors.ts`
- Modify: `src/api/activityApi.ts`
- Modify: `src/api/activityApi.test.ts`

- [ ] **Step 1: Write the failing label test**

Create `src/lib/labels.test.ts`:

```ts
import {
  CATEGORY_LABELS,
  EMPTY_STATE_TEXT,
  NAV_LABELS,
  RULE_SOURCE_LABELS,
  RULE_TYPE_LABELS,
  STATUS_LABELS,
} from "./labels";

describe("Korean labels", () => {
  it("covers all productivity categories with Korean text", () => {
    expect(CATEGORY_LABELS).toEqual({
      productive: "생산적",
      unproductive: "비생산",
      neutral: "중립",
      ignored: "제외",
      uncategorized: "검토 필요",
    });
  });

  it("covers navigation, status, rules, and empty states", () => {
    expect(NAV_LABELS.today).toBe("오늘 요약");
    expect(NAV_LABELS.timeline).toBe("타임라인");
    expect(NAV_LABELS.weekly).toBe("주간 리포트");
    expect(NAV_LABELS.review).toBe("미분류 검토");
    expect(NAV_LABELS.rules).toBe("분류 규칙");
    expect(STATUS_LABELS.readyDesktop).toBe("기록 중");
    expect(RULE_TYPE_LABELS.domain).toBe("도메인");
    expect(RULE_SOURCE_LABELS.builtin).toBe("기본 규칙");
    expect(EMPTY_STATE_TEXT.noUncategorized).toBe("검토할 항목이 없습니다.");
  });
});
```

- [ ] **Step 2: Run the label test and verify failure**

Run:

```powershell
npm test -- src/lib/labels.test.ts
```

Expected: FAIL because `src/lib/labels.ts` does not exist.

- [ ] **Step 3: Create the Korean label layer**

Create `src/lib/labels.ts`:

```ts
import type { ProductivityCategory, RuleType } from "../types/activity";

export const CATEGORY_LABELS: Record<ProductivityCategory, string> = {
  productive: "생산적",
  unproductive: "비생산",
  neutral: "중립",
  ignored: "제외",
  uncategorized: "검토 필요",
};

export const CATEGORY_ACTION_LABELS: Record<Exclude<ProductivityCategory, "uncategorized">, string> = {
  productive: "생산적",
  unproductive: "비생산",
  neutral: "중립",
  ignored: "제외",
};

export const RULE_TYPE_LABELS: Record<RuleType, string> = {
  domain: "도메인",
  app: "앱",
  titleKeyword: "제목 키워드",
  urlPattern: "URL 패턴",
};

export const RULE_SOURCE_LABELS = {
  builtin: "기본 규칙",
  custom: "사용자 규칙",
  none: "규칙 없음",
} as const;

export const NAV_LABELS = {
  today: "오늘 요약",
  timeline: "타임라인",
  weekly: "주간 리포트",
  review: "미분류 검토",
  rules: "분류 규칙",
} as const;

export const STATUS_LABELS = {
  loading: "불러오는 중",
  error: "확인 필요",
  readyDesktop: "기록 중",
  readyDemo: "데모 데이터",
} as const;

export const EMPTY_STATE_TEXT = {
  noActivityToday: "아직 기록된 활동이 없습니다.",
  noCategoryTime: "아직 분류된 시간이 없습니다.",
  noDestinations: "아직 사용 항목이 없습니다.",
  noWeeklyActivity: "아직 주간 활동 기록이 없습니다.",
  noRules: "분류 규칙이 없습니다.",
  noUncategorized: "검토할 항목이 없습니다.",
} as const;
```

- [ ] **Step 4: Keep `src/lib/colors.ts` focused on colors**

Replace `src/lib/colors.ts` with:

```ts
import type { ProductivityCategory } from "../types/activity";

export const CATEGORY_COLORS: Record<ProductivityCategory, string> = {
  productive: "#16a34a",
  unproductive: "#dc2626",
  neutral: "#d97706",
  ignored: "#64748b",
  uncategorized: "#7c3aed",
};

export const IDLE_COLOR = "#64748b";

const NAME_COLORS = [
  "#2563eb",
  "#14b8a6",
  "#84cc16",
  "#f97316",
  "#ef4444",
  "#a855f7",
  "#ec4899",
  "#06b6d4",
  "#22c55e",
  "#eab308",
];

export function colorForName(name: string): string {
  let hash = 0;

  for (let index = 0; index < name.length; index += 1) {
    hash = (hash * 31 + name.charCodeAt(index)) >>> 0;
  }

  return NAME_COLORS[hash % NAME_COLORS.length];
}

export function colorForCategory(category: ProductivityCategory, isIdle = false): string {
  return isIdle ? IDLE_COLOR : CATEGORY_COLORS[category];
}
```

- [ ] **Step 5: Write failing broad-preset tests**

Append to `src/api/activityApi.test.ts`:

```ts
describe("dev fallback default rules", () => {
  it("ships broad editable defaults for common Korean and global services", async () => {
    const names = (await listRules()).map((rule) => rule.name);

    expect(names).toEqual(
      expect.arrayContaining([
        "ChatGPT",
        "Codex",
        "YouTube",
        "Instagram",
        "Chzzk",
        "Naver",
        "Google",
        "GitHub",
      ]),
    );
  });
});
```

- [ ] **Step 6: Run the API test and verify failure**

Run:

```powershell
npm test -- src/api/activityApi.test.ts
```

Expected: FAIL because current dev rules only include ChatGPT and YouTube.

- [ ] **Step 7: Broaden `builtinDevRules` and dev sample data**

In `src/api/activityApi.ts`, replace `builtinDevRules` with this seed-based version:

```ts
const builtinRuleSeeds: Array<Pick<ClassificationRule, "name" | "ruleType" | "pattern" | "category">> = [
  { name: "ChatGPT", ruleType: "domain", pattern: "chatgpt.com", category: "productive" },
  { name: "OpenAI", ruleType: "domain", pattern: "openai.com", category: "productive" },
  { name: "Codex", ruleType: "app", pattern: "codex.exe", category: "productive" },
  { name: "GitHub", ruleType: "domain", pattern: "github.com", category: "productive" },
  { name: "Stack Overflow", ruleType: "domain", pattern: "stackoverflow.com", category: "productive" },
  { name: "Visual Studio Code", ruleType: "app", pattern: "Code.exe", category: "productive" },
  { name: "Google", ruleType: "domain", pattern: "google.com", category: "neutral" },
  { name: "Naver", ruleType: "domain", pattern: "naver.com", category: "neutral" },
  { name: "Google Docs", ruleType: "domain", pattern: "docs.google.com", category: "productive" },
  { name: "Notion", ruleType: "domain", pattern: "notion.so", category: "productive" },
  { name: "YouTube", ruleType: "domain", pattern: "youtube.com", category: "unproductive" },
  { name: "Instagram", ruleType: "domain", pattern: "instagram.com", category: "unproductive" },
  { name: "Chzzk", ruleType: "domain", pattern: "chzzk.naver.com", category: "unproductive" },
  { name: "Twitch", ruleType: "domain", pattern: "twitch.tv", category: "unproductive" },
  { name: "Netflix", ruleType: "domain", pattern: "netflix.com", category: "unproductive" },
];

const builtinDevRules: ClassificationRule[] = builtinRuleSeeds.map((seed) => ({
  id: `builtin:${seed.ruleType}:${seed.pattern}`,
  priority: 0,
  isBuiltin: true,
  isEnabled: true,
  ...seed,
}));
```

Add two more dev sessions to `baseDevSessions`:

```ts
{
  id: "dev-4",
  startedAt: new Date(Date.now() + 93 * 60 * 1000).toISOString(),
  endedAt: new Date(Date.now() + 111 * 60 * 1000).toISOString(),
  durationSeconds: 1080,
  appName: "Chrome",
  processName: "chrome.exe",
  windowTitle: "Naver Search",
  domain: "naver.com",
  isIdle: false,
  category: "neutral",
  matchedRuleId: "builtin:domain:naver.com",
},
{
  id: "dev-5",
  startedAt: new Date(Date.now() + 112 * 60 * 1000).toISOString(),
  endedAt: new Date(Date.now() + 130 * 60 * 1000).toISOString(),
  durationSeconds: 1080,
  appName: "Chrome",
  processName: "chrome.exe",
  windowTitle: "Chzzk",
  domain: "chzzk.naver.com",
  isIdle: false,
  category: "unproductive",
  matchedRuleId: "builtin:domain:chzzk.naver.com",
}
```

- [ ] **Step 8: Run targeted tests**

Run:

```powershell
npm test -- src/lib/labels.test.ts src/api/activityApi.test.ts
```

Expected: PASS.

- [ ] **Step 9: Commit**

```powershell
git add src/lib src/api
git commit -m "feat: add korean labels and broad defaults"
```

## Task 2: Build The Sidebar App Shell

**Files:**
- Create: `src/types/navigation.ts`
- Create: `src/components/layout/AppShell.test.tsx`
- Modify: `src/components/layout/AppShell.tsx`

- [ ] **Step 1: Create page type**

Create `src/types/navigation.ts`:

```ts
export type AppPage = "today" | "timeline" | "weekly" | "review" | "rules";
```

- [ ] **Step 2: Write the failing shell test**

Create `src/components/layout/AppShell.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "./AppShell";

describe("AppShell", () => {
  it("renders Korean sidebar navigation and reports selection changes", async () => {
    const user = userEvent.setup();
    const onPageChange = vi.fn();

    render(
      <AppShell currentPage="today" onPageChange={onPageChange} reviewCount={3} status="ready" statusLabel="기록 중">
        <div>본문</div>
      </AppShell>,
    );

    expect(screen.getByRole("heading", { name: "타임매니저" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "오늘 요약" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("button", { name: "미분류 검토 3" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "타임라인" }));

    expect(onPageChange).toHaveBeenCalledWith("timeline");
  });
});
```

- [ ] **Step 3: Run the shell test and verify failure**

Run:

```powershell
npm test -- src/components/layout/AppShell.test.tsx
```

Expected: FAIL because the current `AppShell` does not accept navigation props.

- [ ] **Step 4: Replace `AppShell.tsx` with sidebar navigation**

Replace `src/components/layout/AppShell.tsx`:

```tsx
import type { PropsWithChildren } from "react";
import { BarChart3, Clock3, Inbox, LayoutDashboard, Settings2 } from "lucide-react";
import { NAV_LABELS } from "../../lib/labels";
import type { AppPage } from "../../types/navigation";

interface AppShellProps extends PropsWithChildren {
  currentPage: AppPage;
  onPageChange: (page: AppPage) => void;
  reviewCount: number;
  status: "loading" | "ready" | "error";
  statusLabel: string;
}

const NAV_ITEMS: Array<{ icon: typeof LayoutDashboard; page: AppPage }> = [
  { page: "today", icon: LayoutDashboard },
  { page: "timeline", icon: Clock3 },
  { page: "weekly", icon: BarChart3 },
  { page: "review", icon: Inbox },
  { page: "rules", icon: Settings2 },
];

export function AppShell({ children, currentPage, onPageChange, reviewCount, status, statusLabel }: AppShellProps) {
  return (
    <div className="app-shell">
      <aside className="app-sidebar" aria-label="주요 화면">
        <div className="sidebar-brand">
          <span className="brand-mark">T</span>
          <div>
            <h1>타임매니저</h1>
            <p>로컬 활동 분석</p>
          </div>
        </div>

        <nav className="sidebar-nav">
          {NAV_ITEMS.map(({ icon: Icon, page }) => {
            const label = NAV_LABELS[page];
            const badge = page === "review" && reviewCount > 0 ? reviewCount : null;

            return (
              <button
                aria-current={currentPage === page ? "page" : undefined}
                className="sidebar-nav-item"
                key={page}
                onClick={() => onPageChange(page)}
                type="button"
              >
                <Icon aria-hidden="true" size={18} strokeWidth={2.2} />
                <span>{label}</span>
                {badge ? <strong className="nav-badge">{badge}</strong> : null}
              </button>
            );
          })}
        </nav>

        <span className={`status-pill status-${status}`}>
          <span aria-hidden="true" className="status-dot" />
          {statusLabel}
        </span>
      </aside>

      <main className="app-main">{children}</main>
    </div>
  );
}
```

- [ ] **Step 5: Run shell test**

Run:

```powershell
npm test -- src/components/layout/AppShell.test.tsx
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add src/types/navigation.ts src/components/layout
git commit -m "feat: add korean sidebar shell"
```

## Task 3: Split The App Into Workflow Pages

**Files:**
- Create: `src/pages/TodayPage.tsx`
- Create: `src/pages/TimelinePage.tsx`
- Create: `src/pages/WeeklyReportPage.tsx`
- Create: `src/pages/ReviewPage.tsx`
- Create: `src/pages/RulesPage.tsx`
- Modify: `src/App.tsx`
- Modify: `src/App.test.tsx`

- [ ] **Step 1: Update `App.test.tsx` for page separation**

Replace the first app test with:

```tsx
it("renders Korean summary page first and separates other workflows behind navigation", async () => {
  const user = userEvent.setup();
  render(<App />);

  expect(screen.getByRole("heading", { name: "타임매니저" })).toBeInTheDocument();
  expect(await screen.findByRole("heading", { name: "오늘 요약" })).toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "분류 규칙" })).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "타임라인" }));
  expect(screen.getByRole("heading", { name: "타임라인" })).toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "오늘 요약" })).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "분류 규칙" }));
  expect(await screen.findByRole("heading", { name: "분류 규칙" })).toBeInTheDocument();
});
```

Update the quick-rule test to navigate to the relevant pages:

```tsx
it("reloads the rules table after a quick rule is created", async () => {
  const user = userEvent.setup();
  vi.mocked(listRules)
    .mockResolvedValueOnce([existingRule])
    .mockResolvedValueOnce([codeRule, existingRule]);
  render(<App />);

  await screen.findByRole("heading", { name: "오늘 요약" });
  await user.click(screen.getByRole("button", { name: "분류 규칙" }));
  expect(await screen.findByText("ChatGPT")).toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "미분류 검토 1" }));
  const reviewRow = screen.getByRole("row", { name: /code/i });
  await user.click(within(reviewRow).getByRole("button", { name: "생산적" }));

  await waitFor(() => expect(listRules).toHaveBeenCalledTimes(2));

  await user.click(screen.getByRole("button", { name: "분류 규칙" }));
  expect(screen.getByRole("row", { name: /Code 앱 Code\.exe 생산적 100 사용자 규칙/i })).toBeInTheDocument();
});
```

- [ ] **Step 2: Run the app test and verify failure**

Run:

```powershell
npm test -- src/App.test.tsx
```

Expected: FAIL because the app still renders every section on one page and still uses English labels.

- [ ] **Step 3: Create page components**

Create `src/pages/TodayPage.tsx`:

```tsx
import { TodaySummary } from "../components/dashboard/TodaySummary";
import { WeeklyTrends } from "../components/dashboard/WeeklyTrends";
import { UsageTable } from "../components/tables/UsageTable";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../types/activity";

interface TodayPageProps {
  sessions: ActivitySession[];
  summary: TodaySummaryDto;
}

export function TodayPage({ sessions, summary }: TodayPageProps) {
  return (
    <div className="page-stack">
      <TodaySummary sessions={sessions} summary={summary} />
      <div className="dashboard-grid today-lower-grid">
        <UsageTable description="가장 많이 사용한 앱과 사이트 5개" maxRows={5} sessions={sessions} title="상위 사용 항목" />
        <WeeklyTrends compact sessions={sessions} summary={summary} />
      </div>
    </div>
  );
}
```

Create `src/pages/TimelinePage.tsx`:

```tsx
import { DayTimeline } from "../components/dashboard/DayTimeline";
import { UsageTable } from "../components/tables/UsageTable";
import type { ActivitySession } from "../types/activity";

interface TimelinePageProps {
  sessions: ActivitySession[];
}

export function TimelinePage({ sessions }: TimelinePageProps) {
  return (
    <div className="page-stack">
      <DayTimeline sessions={sessions} />
      <UsageTable description="타임라인에 포함된 활동을 시간순 사용량으로 정리했습니다." sessions={sessions} title="타임라인 활동 목록" />
    </div>
  );
}
```

Create `src/pages/WeeklyReportPage.tsx`:

```tsx
import { WeeklyTrends } from "../components/dashboard/WeeklyTrends";
import { UsageTable } from "../components/tables/UsageTable";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "../types/activity";

interface WeeklyReportPageProps {
  sessions: ActivitySession[];
  summary: TodaySummaryDto;
}

export function WeeklyReportPage({ sessions, summary }: WeeklyReportPageProps) {
  return (
    <div className="page-stack">
      <WeeklyTrends sessions={sessions} summary={summary} />
      <UsageTable description="리포트에 포함된 앱과 사이트를 사용 시간 기준으로 정렬했습니다." sessions={sessions} title="앱과 사이트 리포트" />
    </div>
  );
}
```

Create `src/pages/ReviewPage.tsx`:

```tsx
import { UncategorizedReview } from "../components/rules/UncategorizedReview";
import type { ActivitySession } from "../types/activity";

interface ReviewPageProps {
  onRuleCreated: () => void;
  sessions: ActivitySession[];
}

export function ReviewPage({ onRuleCreated, sessions }: ReviewPageProps) {
  return <UncategorizedReview onRuleCreated={onRuleCreated} sessions={sessions} />;
}
```

Create `src/pages/RulesPage.tsx`:

```tsx
import { RulesSettings } from "../components/rules/RulesSettings";

interface RulesPageProps {
  refreshVersion: number;
}

export function RulesPage({ refreshVersion }: RulesPageProps) {
  return <RulesSettings refreshVersion={refreshVersion} />;
}
```

- [ ] **Step 4: Refactor `App.tsx` to render one page at a time**

Replace `src/App.tsx`:

```tsx
import { useCallback, useEffect, useMemo, useState } from "react";
import { getTodaySessions, getTodaySummary } from "./api/activityApi";
import { AppShell } from "./components/layout/AppShell";
import { EMPTY_STATE_TEXT, NAV_LABELS, STATUS_LABELS } from "./lib/labels";
import { ReviewPage } from "./pages/ReviewPage";
import { RulesPage } from "./pages/RulesPage";
import { TimelinePage } from "./pages/TimelinePage";
import { TodayPage } from "./pages/TodayPage";
import { WeeklyReportPage } from "./pages/WeeklyReportPage";
import type { AppPage } from "./types/navigation";
import type { ActivitySession, TodaySummary as TodaySummaryDto } from "./types/activity";
import "./styles.css";

type DashboardState =
  | { status: "loading" }
  | { sessions: ActivitySession[]; status: "ready"; summary: TodaySummaryDto }
  | { message: string; status: "error" };

export default function App() {
  const [currentPage, setCurrentPage] = useState<AppPage>("today");
  const [dashboardState, setDashboardState] = useState<DashboardState>({ status: "loading" });
  const [rulesRefreshVersion, setRulesRefreshVersion] = useState(0);

  const loadDashboard = useCallback(async (shouldApply = () => true) => {
    try {
      const [summary, sessions] = await Promise.all([getTodaySummary(), getTodaySessions()]);
      if (shouldApply()) {
        setDashboardState({ sessions, status: "ready", summary });
      }
    } catch (error) {
      if (shouldApply()) {
        setDashboardState({
          message: error instanceof Error ? error.message : "활동 데이터를 불러오지 못했습니다.",
          status: "error",
        });
      }
    }
  }, []);

  useEffect(() => {
    let isMounted = true;
    void loadDashboard(() => isMounted);
    return () => {
      isMounted = false;
    };
  }, [loadDashboard]);

  const isDesktopRuntime = "__TAURI_INTERNALS__" in window;
  const statusLabel =
    dashboardState.status === "loading"
      ? STATUS_LABELS.loading
      : dashboardState.status === "error"
        ? STATUS_LABELS.error
        : isDesktopRuntime
          ? STATUS_LABELS.readyDesktop
          : STATUS_LABELS.readyDemo;

  const reviewCount = useMemo(() => {
    if (dashboardState.status !== "ready") {
      return 0;
    }
    const keys = new Set(
      dashboardState.sessions
        .filter((session) => session.category === "uncategorized")
        .map((session) => `${session.domain ? "domain" : "app"}:${session.domain ?? session.processName}`),
    );
    return keys.size;
  }, [dashboardState]);

  function handleRuleCreated() {
    setRulesRefreshVersion((version) => version + 1);
    void loadDashboard();
  }

  return (
    <AppShell
      currentPage={currentPage}
      onPageChange={setCurrentPage}
      reviewCount={reviewCount}
      status={dashboardState.status}
      statusLabel={statusLabel}
    >
      {dashboardState.status === "loading" ? (
        <section className="panel state-panel" aria-live="polite">
          <h2>활동 기록을 불러오는 중입니다</h2>
          <p>오늘 요약 화면을 준비하고 있습니다.</p>
        </section>
      ) : null}

      {dashboardState.status === "error" ? (
        <section className="panel state-panel error-panel" aria-live="assertive">
          <h2>활동 데이터를 불러오지 못했습니다</h2>
          <p>{dashboardState.message}</p>
        </section>
      ) : null}

      {dashboardState.status === "ready" ? (
        <>
          <header className="page-header">
            <div>
              <p>활동 분석</p>
              <h2>{NAV_LABELS[currentPage]}</h2>
            </div>
            <span>{dashboardState.sessions.length > 0 ? `${dashboardState.sessions.length}개 세션` : EMPTY_STATE_TEXT.noActivityToday}</span>
          </header>

          {currentPage === "today" ? <TodayPage sessions={dashboardState.sessions} summary={dashboardState.summary} /> : null}
          {currentPage === "timeline" ? <TimelinePage sessions={dashboardState.sessions} /> : null}
          {currentPage === "weekly" ? <WeeklyReportPage sessions={dashboardState.sessions} summary={dashboardState.summary} /> : null}
          {currentPage === "review" ? <ReviewPage onRuleCreated={handleRuleCreated} sessions={dashboardState.sessions} /> : null}
          {currentPage === "rules" ? <RulesPage refreshVersion={rulesRefreshVersion} /> : null}
        </>
      ) : null}
    </AppShell>
  );
}
```

- [ ] **Step 5: Run app tests**

Run:

```powershell
npm test -- src/App.test.tsx
```

Expected: app tests still fail until component labels and `UsageTable`/`WeeklyTrends` props are updated in the next task.

- [ ] **Step 6: Commit after Task 4 passes**

Do not commit this task until Task 4 makes the app compile and tests pass. Commit Task 3 and Task 4 together with:

```powershell
git add src/App.tsx src/App.test.tsx src/pages
git commit -m "feat: split dashboard into korean pages"
```

## Task 4: Koreanize Dashboard, Table, And Report Components

**Files:**
- Modify: `src/components/dashboard/TodaySummary.tsx`
- Modify: `src/components/dashboard/TodaySummary.test.tsx`
- Modify: `src/components/dashboard/DayTimeline.tsx`
- Modify: `src/components/dashboard/DayTimeline.test.tsx`
- Modify: `src/components/dashboard/WeeklyTrends.tsx`
- Modify: `src/components/dashboard/WeeklyTrends.test.tsx`
- Modify: `src/components/tables/UsageTable.tsx`
- Modify: `src/components/tables/UsageTable.test.tsx`

- [ ] **Step 1: Update component tests to Korean expectations**

Apply these expectation changes:

```tsx
// TodaySummary.test.tsx
expect(screen.getAllByText("제외").length).toBeGreaterThan(0);
expect(screen.getByText("아직 분류된 시간이 없습니다.")).toBeInTheDocument();
expect(screen.getByText("아직 사용 항목이 없습니다.")).toBeInTheDocument();

// DayTimeline.test.tsx
expect(screen.getByRole("list", { name: "오늘 활동 세션 타임라인" })).toBeInTheDocument();

// WeeklyTrends.test.tsx
expect(screen.getByText("제외")).toBeInTheDocument();
expect(screen.getByText("아직 주간 활동 기록이 없습니다.")).toBeInTheDocument();

// UsageTable.test.tsx
expect(within(row).getByText("생산적")).toBeInTheDocument();
expect(within(row).queryByText("비생산")).not.toBeInTheDocument();
expect(screen.getByText("유휴")).toBeInTheDocument();
expect(screen.getByText("아직 사용 항목이 없습니다.")).toBeInTheDocument();
```

- [ ] **Step 2: Run component tests and verify failure**

Run:

```powershell
npm test -- src/components/dashboard src/components/tables
```

Expected: FAIL because components still use English labels.

- [ ] **Step 3: Update `TodaySummary.tsx` imports and metric text**

Change imports:

```ts
import { CATEGORY_COLORS, IDLE_COLOR, colorForName } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
```

Replace the `metrics` array with:

```ts
const metrics: MetricCard[] = [
  {
    label: "총 기록 시간",
    value: formatDuration(trackedTotal),
    detail: `${sessions.length}개 세션`,
    color: "#2563eb",
  },
  {
    label: "생산적 사용",
    value: formatDuration(summary.productiveSeconds),
    detail: `활동 시간 중 ${focusRatio}`,
    color: CATEGORY_COLORS.productive,
  },
  {
    label: "비생산 사용",
    value: formatDuration(summary.unproductiveSeconds),
    detail: `활동 시간 중 ${percent(summary.unproductiveSeconds, activeTotal)}`,
    color: CATEGORY_COLORS.unproductive,
  },
  {
    label: "유휴 시간",
    value: formatDuration(summary.idleSeconds),
    detail: `기록 시간 중 ${percent(summary.idleSeconds, trackedTotal)}`,
    color: IDLE_COLOR,
  },
];
```

Replace headings and empty states:

```tsx
<h2 id="today-summary-title">오늘 요약</h2>
<p>활동 시간 중 {focusRatio} 생산적 사용</p>
<div className="chart-surface" role="img" aria-label="생산성 분류 도넛 차트">
<p className="empty-state chart-empty-state">{EMPTY_STATE_TEXT.noCategoryTime}</p>
<div className="chart-surface" role="img" aria-label="상위 사용 항목 막대 차트">
<p className="empty-state chart-empty-state">{EMPTY_STATE_TEXT.noDestinations}</p>
```

Change the idle breakdown name:

```ts
{
  name: "유휴",
  seconds: summary.idleSeconds,
  color: IDLE_COLOR,
}
```

- [ ] **Step 4: Update `DayTimeline.tsx`**

Change imports:

```ts
import { colorForCategory } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
```

Use Korean date formatting:

```ts
const timeFormatter = new Intl.DateTimeFormat("ko-KR", {
  hour: "numeric",
  minute: "2-digit",
});
```

Replace visible and accessible text:

```tsx
<h2 id="timeline-title">타임라인</h2>
<p>{sortedSessions.length}개 세션 기록</p>
<div className="timeline-track" aria-label="오늘 활동 세션 타임라인" role="list">
const categoryLabel = session.isIdle ? "유휴" : CATEGORY_LABELS[session.category];
<p className="empty-state">{EMPTY_STATE_TEXT.noActivityToday}</p>
```

- [ ] **Step 5: Update `WeeklyTrends.tsx`**

Change imports:

```ts
import { CATEGORY_COLORS, IDLE_COLOR } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT } from "../../lib/labels";
```

Change props:

```ts
interface WeeklyTrendsProps {
  compact?: boolean;
  sessions: ActivitySession[];
  summary: TodaySummaryDto;
}
```

Change day formatter and headings:

```ts
const dayFormatter = new Intl.DateTimeFormat("ko-KR", { weekday: "short" });

export function WeeklyTrends({ compact = false, sessions, summary }: WeeklyTrendsProps) {
```

Replace visible labels:

```tsx
<h2 id="weekly-trends-title">{compact ? "주간 흐름" : "주간 리포트"}</h2>
<p>분류별 사용 시간과 생산성 비율</p>
<div className="trend-chart" role="img" aria-label="주간 분류별 사용 시간과 생산성 비율 차트">
```

Replace tooltip formatter:

```ts
formatter={(value, name) => {
  if (name === "ratio") {
    return [`${Number(value)}%`, "생산성 비율"];
  }

  const label = name === "idle" ? "유휴" : CATEGORY_LABELS[name as keyof typeof CATEGORY_LABELS];
  return [formatDuration(Number(value)), label];
}}
```

Add `name` props to chart series:

```tsx
<Bar yAxisId="time" dataKey="productive" name={CATEGORY_LABELS.productive} stackId="time" fill={CATEGORY_COLORS.productive} />
<Bar yAxisId="time" dataKey="unproductive" name={CATEGORY_LABELS.unproductive} stackId="time" fill={CATEGORY_COLORS.unproductive} />
<Bar yAxisId="time" dataKey="neutral" name={CATEGORY_LABELS.neutral} stackId="time" fill={CATEGORY_COLORS.neutral} />
<Bar yAxisId="time" dataKey="ignored" name={CATEGORY_LABELS.ignored} stackId="time" fill={CATEGORY_COLORS.ignored} />
<Bar yAxisId="time" dataKey="uncategorized" name={CATEGORY_LABELS.uncategorized} stackId="time" fill={CATEGORY_COLORS.uncategorized} />
<Bar yAxisId="time" dataKey="idle" name="유휴" stackId="time" fill={IDLE_COLOR} />
<Line yAxisId="ratio" type="monotone" dataKey="ratio" name="생산성 비율" stroke="#111827" strokeWidth={2} dot={{ r: 3 }} activeDot={{ r: 5 }} />
```

Replace the empty state:

```tsx
<p className="empty-state chart-empty-state">{EMPTY_STATE_TEXT.noWeeklyActivity}</p>
```

- [ ] **Step 6: Update `UsageTable.tsx`**

Change imports:

```ts
import { colorForCategory } from "../../lib/colors";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT, RULE_SOURCE_LABELS } from "../../lib/labels";
```

Change props:

```ts
interface UsageTableProps {
  description?: string;
  maxRows?: number;
  sessions: ActivitySession[];
  title?: string;
}
```

Change matched rule default and exported component:

```ts
matchedRule: [...group.matchedRules][0] ?? RULE_SOURCE_LABELS.none,

export function UsageTable({ description = "앱과 사이트를 사용 시간 기준으로 정리했습니다.", maxRows, sessions, title = "상위 앱과 사이트" }: UsageTableProps) {
  const rows = buildRows(sessions).slice(0, maxRows ?? Number.POSITIVE_INFINITY);
```

Replace heading, table headers, labels, and empty state:

```tsx
<h2 id="usage-table-title">{title}</h2>
<p>{description}</p>
<th scope="col">이름</th>
<th scope="col">분류</th>
<th scope="col">시간</th>
<th scope="col">비중</th>
<th scope="col">적용 규칙</th>
{row.isIdle ? "유휴" : CATEGORY_LABELS[row.category]}
<span className="share-meter" aria-label={`${Math.round(row.share * 100)}퍼센트`}>
<p className="empty-state table-empty-state">{EMPTY_STATE_TEXT.noDestinations}</p>
```

- [ ] **Step 7: Run dashboard/table tests**

Run:

```powershell
npm test -- src/components/dashboard src/components/tables src/App.test.tsx
```

Expected: PASS.

- [ ] **Step 8: Commit Task 3 and Task 4 together**

```powershell
git add src/App.tsx src/App.test.tsx src/pages src/components/dashboard src/components/tables
git commit -m "feat: split dashboard into korean pages"
```

## Task 5: Koreanize Rule Customization And Review Queue

**Files:**
- Modify: `src/components/rules/RulesSettings.tsx`
- Modify: `src/components/rules/RulesSettings.test.tsx`
- Modify: `src/components/rules/UncategorizedReview.tsx`
- Modify: `src/components/rules/UncategorizedReview.test.tsx`

- [ ] **Step 1: Update rule tests to Korean labels**

Apply these test expectation changes:

```tsx
// RulesSettings.test.tsx
expect(screen.getByRole("option", { name: "URL 패턴" })).toBeInTheDocument();
await user.selectOptions(screen.getByLabelText("규칙 종류"), "urlPattern");
await user.selectOptions(screen.getByLabelText("분류"), "unproductive");
await user.type(screen.getByLabelText("패턴"), "/watch");
await user.click(screen.getByRole("button", { name: "규칙 추가" }));
expect(within(rows[1]).getByText("비생산")).toBeInTheDocument();
const patternInput = await screen.findByLabelText("패턴");
expect(error).toHaveTextContent("패턴을 입력해야 합니다.");

// UncategorizedReview.test.tsx
await user.click(within(row).getByRole("button", { name: "생산적" }));
await user.click(within(row).getByRole("button", { name: "중립" }));
expect(within(row).getByText("2개 세션")).toBeInTheDocument();
await user.click(within(row).getByRole("button", { name: "제외" }));
expect(screen.getByText("0개 항목 검토 필요")).toBeInTheDocument();
expect(screen.getByText("검토할 항목이 없습니다.")).toBeInTheDocument();
```

- [ ] **Step 2: Run rule tests and verify failure**

Run:

```powershell
npm test -- src/components/rules
```

Expected: FAIL because the rule UI is still English.

- [ ] **Step 3: Update `RulesSettings.tsx` labels and layout classes**

Change imports:

```ts
import { CATEGORY_LABELS, EMPTY_STATE_TEXT, RULE_SOURCE_LABELS, RULE_TYPE_LABELS } from "../../lib/labels";
```

Remove local `RULE_TYPE_LABELS`. Keep:

```ts
const RULE_TYPES: RuleType[] = ["domain", "app", "titleKeyword", "urlPattern"];
const RULE_CATEGORIES: ProductivityCategory[] = ["productive", "unproductive", "neutral", "ignored"];
```

Replace fallback and validation strings:

```ts
message: error instanceof Error ? error.message : "분류 규칙을 불러오지 못했습니다.",
setFormError("패턴을 입력해야 합니다.");
setFormError(error instanceof Error ? error.message : "규칙을 만들지 못했습니다.");
```

Replace heading and form labels:

```tsx
<h2 id="rules-settings-title">분류 규칙</h2>
<p>{rulesState.status === "ready" ? `${rules.length}개 규칙` : "도메인, 앱, 제목 키워드 규칙"}</p>
<form className="rule-form" onSubmit={handleSubmit}>
  <label>
    <span>규칙 종류</span>
  </label>
  <label>
    <span>패턴</span>
  </label>
  <label>
    <span>분류</span>
  </label>
  <button type="submit" disabled={isSaving || !pattern.trim()}>
    {isSaving ? "저장 중" : "규칙 추가"}
  </button>
</form>
```

Replace table headers and values:

```tsx
<th scope="col">이름</th>
<th scope="col">종류</th>
<th scope="col">패턴</th>
<th scope="col">분류</th>
<th scope="col">우선순위</th>
<th scope="col">출처</th>
<td>{RULE_TYPE_LABELS[rule.ruleType]}</td>
<td>{CATEGORY_LABELS[rule.category]}</td>
<td>{rule.isBuiltin ? RULE_SOURCE_LABELS.builtin : RULE_SOURCE_LABELS.custom}</td>
```

Replace states:

```tsx
{rulesState.status === "loading" ? <p className="empty-state table-empty-state">분류 규칙을 불러오는 중입니다.</p> : null}
{rulesState.status === "ready" && rules.length === 0 ? <p className="empty-state table-empty-state">{EMPTY_STATE_TEXT.noRules}</p> : null}
```

- [ ] **Step 4: Update `UncategorizedReview.tsx` labels**

Change imports:

```ts
import { CATEGORY_ACTION_LABELS, EMPTY_STATE_TEXT, RULE_TYPE_LABELS } from "../../lib/labels";
```

Replace target count label:

```ts
const targetCountLabel = `${reviewTargets.length}개 항목 검토 필요`;
```

Replace error fallback:

```ts
setError(caughtError instanceof Error ? caughtError.message : "규칙을 만들지 못했습니다.");
```

Replace heading and table labels:

```tsx
<h2 id="uncategorized-review-title">미분류 검토</h2>
<th scope="col">이름</th>
<th scope="col">종류</th>
<th scope="col">시간</th>
<th scope="col">작업</th>
<span className="review-target-count">{target.count}개 세션</span>
<td>{RULE_TYPE_LABELS[target.ruleType]}</td>
{creatingRule === `${target.key}:${category}` ? "저장 중" : CATEGORY_ACTION_LABELS[category]}
<p className="empty-state table-empty-state">{EMPTY_STATE_TEXT.noUncategorized}</p>
```

- [ ] **Step 5: Run rule tests**

Run:

```powershell
npm test -- src/components/rules src/App.test.tsx
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add src/components/rules
git commit -m "feat: koreanize rules and review queue"
```

## Task 6: Apply Professional Desktop Visual Design

**Files:**
- Modify: `src/styles.css`
- Modify: `tests/e2e/dashboard.spec.ts`

- [ ] **Step 1: Update e2e expectations for separated Korean screens**

Replace `tests/e2e/dashboard.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("dashboard renders professional Korean analytics shell", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "타임매니저" })).toBeVisible();
  await expect(page.getByRole("button", { name: "오늘 요약" })).toHaveAttribute("aria-current", "page");
  await expect(page.getByRole("heading", { name: "오늘 요약" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "상위 사용 항목" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "분류 규칙" })).toHaveCount(0);

  const cards = page.locator(".metric-card");
  await expect(cards).toHaveCount(4);
  await expect(cards.locator("span").filter({ hasText: /^총 기록 시간$/ })).toBeVisible();
  await expect(cards.locator("span").filter({ hasText: /^생산적 사용$/ })).toBeVisible();
  await expect(cards.locator("span").filter({ hasText: /^비생산 사용$/ })).toBeVisible();

  const borderColors = await cards.evaluateAll((elements) =>
    elements.map((element) => getComputedStyle(element).borderLeftColor),
  );
  expect(new Set(borderColors).size).toBeGreaterThanOrEqual(3);

  await page.getByRole("button", { name: "분류 규칙" }).click();
  await expect(page.getByRole("heading", { name: "분류 규칙" })).toBeVisible();
  await expect(page.getByLabel("규칙 종류")).toBeVisible();
});
```

- [ ] **Step 2: Run e2e and verify failure**

Run:

```powershell
npm run e2e
```

Expected: FAIL until layout and Korean text are complete.

- [ ] **Step 3: Replace the shell and page layout CSS**

In `src/styles.css`, replace the old `.topbar`, `.dashboard-main`, and related shell rules with:

```css
:root {
  color: #172033;
  background: #eef3f8;
  font-family: Pretendard, "Segoe UI", "Apple SD Gothic Neo", ui-sans-serif, system-ui, sans-serif;
}

body {
  min-width: 320px;
  min-height: 100vh;
  background: #eef3f8;
  color: #172033;
}

.app-shell {
  display: grid;
  grid-template-columns: 232px minmax(0, 1fr);
  min-height: 100vh;
}

.app-sidebar {
  position: sticky;
  top: 0;
  display: flex;
  flex-direction: column;
  gap: 22px;
  height: 100vh;
  padding: 22px 16px;
  background: #111827;
  color: #f8fafc;
}

.sidebar-brand {
  display: flex;
  align-items: center;
  gap: 11px;
}

.brand-mark {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border-radius: 8px;
  background: #2563eb;
  font-weight: 900;
}

.sidebar-brand h1 {
  margin: 0;
  font-size: 1.08rem;
  letter-spacing: 0;
}

.sidebar-brand p {
  margin: 2px 0 0;
  color: #94a3b8;
  font-size: 0.78rem;
  font-weight: 700;
}

.sidebar-nav {
  display: grid;
  gap: 8px;
}

.sidebar-nav-item {
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr) auto;
  align-items: center;
  gap: 10px;
  min-height: 42px;
  padding: 9px 10px;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: #cbd5e1;
  text-align: left;
  font-weight: 800;
  cursor: pointer;
}

.sidebar-nav-item[aria-current="page"] {
  background: #2563eb;
  color: #ffffff;
}

.nav-badge {
  min-width: 24px;
  padding: 3px 7px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.18);
  text-align: center;
  font-size: 0.74rem;
}

.app-main {
  min-width: 0;
  padding: 22px;
}

.page-header {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.page-header p,
.page-header span {
  margin: 0;
  color: #64748b;
  font-size: 0.84rem;
  font-weight: 800;
}

.page-header h2 {
  margin: 4px 0 0;
  font-size: 1.55rem;
  letter-spacing: 0;
}

.page-stack {
  display: grid;
  gap: 16px;
}
```

- [ ] **Step 4: Keep panel, card, chart, and table styles professional**

Update these existing selectors in `src/styles.css`:

```css
.panel {
  background: #ffffff;
  border: 1px solid #dce5ee;
  border-radius: 8px;
  box-shadow: 0 14px 34px rgba(15, 23, 42, 0.08);
}

.metric-card {
  min-width: 0;
  padding: 13px 13px 12px;
  border: 1px solid #e2e8f0;
  border-left: 5px solid var(--metric-color);
  border-radius: 8px;
  background: #fbfdff;
}

.metric-card span {
  color: #617487;
  font-size: 0.78rem;
  font-weight: 900;
  text-transform: none;
}

.usage-table thead th {
  color: #53697e;
  background: #f7fafc;
  font-size: 0.76rem;
  font-weight: 900;
  text-transform: none;
}

.rule-form {
  display: grid;
  grid-template-columns: repeat(4, minmax(150px, 1fr));
  gap: 10px;
  align-items: end;
  padding: 14px 16px;
  border-bottom: 1px solid #e6edf4;
}
```

- [ ] **Step 5: Add responsive sidebar and rule form behavior**

Append:

```css
@media (max-width: 1050px) {
  .app-shell {
    grid-template-columns: 78px minmax(0, 1fr);
  }

  .sidebar-brand div,
  .sidebar-nav-item span {
    display: none;
  }

  .sidebar-nav-item {
    grid-template-columns: 1fr;
    justify-items: center;
  }

  .nav-badge {
    position: absolute;
    margin-left: 24px;
  }

  .rule-form {
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 760px) {
  .app-shell {
    grid-template-columns: 1fr;
  }

  .app-sidebar {
    position: static;
    height: auto;
    padding: 14px;
  }

  .sidebar-brand div {
    display: block;
  }

  .sidebar-nav {
    grid-template-columns: repeat(5, minmax(44px, 1fr));
  }

  .sidebar-nav-item {
    min-height: 46px;
    padding: 8px;
  }

  .app-main {
    padding: 14px 12px 24px;
  }

  .page-header {
    align-items: start;
    flex-direction: column;
  }

  .metric-grid,
  .summary-chart-grid,
  .dashboard-grid,
  .rule-form {
    grid-template-columns: 1fr;
  }
}
```

- [ ] **Step 6: Run unit tests and e2e**

Run:

```powershell
npm test
npm run e2e
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add src/styles.css tests/e2e/dashboard.spec.ts
git commit -m "style: apply professional korean desktop layout"
```

## Task 7: Final Verification With Build And Screenshots

**Files:**
- Modify only files required by failures found during verification.

- [ ] **Step 1: Run unit tests**

Run:

```powershell
npm test
```

Expected: PASS.

- [ ] **Step 2: Run production build**

Run:

```powershell
npm run build
```

Expected: PASS.

- [ ] **Step 3: Run Playwright**

Run:

```powershell
npm run e2e
```

Expected: PASS.

- [ ] **Step 4: Launch the app for visual inspection**

Run:

```powershell
npm run tauri dev
```

Expected: the Windows app opens with a dark sidebar, Korean text, Today Summary as the first page, and separated navigation for Timeline, Weekly Report, Uncategorized Review, and Rules.

- [ ] **Step 5: Capture desktop and narrow screenshots**

Use the existing Playwright/native screenshot workflow from prior verification, saving images under:

```text
test-results/native-shots/professional-korean-desktop.png
test-results/native-shots/professional-korean-narrow.png
```

Expected:

- Desktop screenshot shows sidebar navigation, four metric cards, charts, a table, and no text overlap.
- Narrow screenshot shows responsive navigation and no rule-form overlap.
- Korean labels are visible across headings, cards, table headers, empty states, and rule controls.

- [ ] **Step 6: Commit verification fixes if any were needed**

If verification required changes:

```powershell
git add src tests
git commit -m "fix: complete korean ui verification"
```

If no changes were needed, do not create an empty commit.

## Self-Review

Spec coverage:

- Professional sidebar-based structure: Task 2 and Task 6.
- One-screen overload removed: Task 3 separates Today, Timeline, Weekly Report, Review, and Rules.
- Charts and tables remain central: Task 4 keeps Today Summary, Weekly Trends, and Usage Table visible in appropriate pages.
- Korean text: Task 1, Task 4, and Task 5 cover labels, empty states, headings, forms, buttons, tables, chart labels, and status text.
- Broad default services: Task 1 adds ChatGPT, Codex, YouTube, Instagram, Chzzk, Naver, Google, GitHub, and related defaults.
- User customization remains available: Task 5 preserves `createRule`, `listRules`, quick review actions, and the rules table.
- Responsive/no-overlap verification: Task 6 e2e and Task 7 screenshots cover desktop and narrow layouts.

Placeholder scan:

- The plan contains no unfinished implementation markers.
- Each code-changing task includes concrete code snippets, target files, commands, and expected outcomes.

Type consistency:

- Navigation uses `AppPage` values matching `NAV_LABELS`.
- Category labels use existing `ProductivityCategory` values.
- Rule type labels use existing `RuleType` values.
- Existing API command wrappers remain unchanged except for dev fallback presets and Korean-safe error text.
