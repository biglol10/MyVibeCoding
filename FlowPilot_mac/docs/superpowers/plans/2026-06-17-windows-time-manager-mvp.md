# Windows Time Manager MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Windows-first local desktop MVP for automatic activity tracking, customizable productivity rules, colorful charts, tables, timelines, pause controls, export, and an optional browser URL bridge.

**Architecture:** Use a Tauri 2 desktop app with a React/TypeScript frontend and Rust backend. Rust owns collection, session merging, classification, SQLite persistence, tray controls, export, and Tauri commands; React owns charts, tables, filtering, and rule editing. Browser URL data is optional and flows through a local bridge so the app still works from process/title fallback.

**Tech Stack:** Tauri 2, React, TypeScript, Vite, Rust, SQLite via `rusqlite`, Windows APIs via the `windows` crate, Vitest, React Testing Library, Playwright, Recharts, lucide-react.

---

## Source Notes

- Tauri project setup: https://v2.tauri.app/start/create-project/
- Vitest setup: https://vitest.dev/guide/
- Playwright setup: https://playwright.dev/docs/intro
- ManicTime day view reference: https://docs.manictime.com/win-client/overview

## File Structure

Create and maintain these boundaries:

- `src-tauri/src/domain/activity.rs`: shared Rust domain types for sessions, categories, summaries, and filters.
- `src-tauri/src/domain/rules.rs`: classification rule types and match ordering.
- `src-tauri/src/domain/classifier.rs`: pure rule matching and classification logic.
- `src-tauri/src/domain/presets.rs`: built-in editable default rule presets.
- `src-tauri/src/storage/schema.rs`: SQLite schema creation and migrations.
- `src-tauri/src/storage/repository.rs`: SQLite reads/writes for sessions, rules, aggregates, settings, and browser events.
- `src-tauri/src/collector/session_merger.rs`: pure logic that merges samples into sessions.
- `src-tauri/src/collector/idle.rs`: idle detector trait and Windows implementation.
- `src-tauri/src/collector/active_window.rs`: active-window trait and Windows implementation.
- `src-tauri/src/collector/service.rs`: background collector loop that samples and persists activity.
- `src-tauri/src/commands.rs`: Tauri command API consumed by React.
- `src-tauri/src/export.rs`: JSON/CSV export logic.
- `src-tauri/src/tray.rs`: tray menu and pause/resume actions.
- `src-tauri/src/app_state.rs`: shared app state, DB handle, collector status, and settings.
- `src-tauri/src/lib.rs`: module registration and Tauri builder setup.
- `src-tauri/src/main.rs`: thin executable entrypoint.
- `src/types/activity.ts`: frontend DTOs mirroring Rust command responses.
- `src/api/activityApi.ts`: typed Tauri command wrappers plus dev fallback.
- `src/lib/time.ts`: duration/date formatting helpers.
- `src/lib/colors.ts`: category and stable entity color helpers.
- `src/components/dashboard/TodaySummary.tsx`: metric cards, donut chart, stacked bar.
- `src/components/dashboard/DayTimeline.tsx`: colorful timeline with filters and segment details.
- `src/components/dashboard/WeeklyTrends.tsx`: weekly stacked bars and productivity line.
- `src/components/tables/UsageTable.tsx`: top apps/sites and recent sessions table.
- `src/components/rules/RulesSettings.tsx`: rule list and editor.
- `src/components/rules/UncategorizedReview.tsx`: uncategorized rows with quick actions.
- `src/components/layout/AppShell.tsx`: navigation, tracking status, and page layout.
- `src/App.tsx`: route/view state composition.
- `src/App.test.tsx`: smoke and interaction tests for the app shell.
- `src/styles.css`: product-level responsive visual system.
- `browser-extension/manifest.json`: Chrome/Edge Manifest V3 extension manifest.
- `browser-extension/src/background.ts`: active tab capture and native bridge client.
- `browser-extension/src/background.test.ts`: URL sanitization tests.
- `tests/e2e/dashboard.spec.ts`: Playwright dashboard rendering tests.

## Task 1: Scaffold Tauri, React, TypeScript, and Test Tooling

**Files:**
- Create: `package.json`
- Create: `vite.config.ts`
- Create: `index.html`
- Create: `src/main.tsx`
- Create: `src/App.tsx`
- Create: `src/App.test.tsx`
- Create: `src/setupTests.ts`
- Create: `src-tauri/Cargo.toml`
- Create: `src-tauri/tauri.conf.json`
- Modify: `.gitignore`

- [ ] **Step 1: Create the Vite React scaffold**

Run:

```powershell
npm create vite@latest . -- --template react-ts
```

If Vite asks how to handle the non-empty directory, choose to keep existing files and continue. Expected: files for a React TypeScript Vite app appear in the repository root while existing `docs/` and `.git/` content remains.

- [ ] **Step 2: Install frontend dependencies**

Run:

```powershell
npm install
npm install recharts lucide-react clsx @tauri-apps/api
npm install -D @tauri-apps/cli@latest vitest jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event playwright
```

Expected: `package-lock.json` updates and `node_modules` is created.

- [ ] **Step 3: Initialize Tauri**

Run:

```powershell
npx tauri init
```

Prompt answers:

```text
What is your app name? Time Manager
What should the window title be? Time Manager
Where are your web assets located? ../dist
What is the url of your dev server? http://localhost:5173
What is your frontend dev command? npm run dev
What is your frontend build command? npm run build
```

Expected: `src-tauri/` is created.

- [ ] **Step 4: Add test scripts to `package.json`**

Set the scripts block to include:

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "e2e": "playwright test",
    "tauri": "tauri"
  }
}
```

- [ ] **Step 5: Configure Vitest in `vite.config.ts`**

Use this file shape:

```ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: "./src/setupTests.ts",
  },
});
```

- [ ] **Step 6: Create `src/setupTests.ts`**

```ts
import "@testing-library/jest-dom/vitest";
```

- [ ] **Step 7: Add an app smoke test**

Create `src/App.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import App from "./App";

describe("App", () => {
  it("renders the dashboard shell", () => {
    render(<App />);
    expect(screen.getByRole("heading", { name: /time manager/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 8: Replace `src/App.tsx` with a minimal shell**

```tsx
export default function App() {
  return (
    <main>
      <h1>Time Manager</h1>
      <p>Automatic local activity tracking dashboard.</p>
    </main>
  );
}
```

- [ ] **Step 9: Run frontend tests**

Run:

```powershell
npm test
```

Expected: `src/App.test.tsx` passes.

- [ ] **Step 10: Run Rust tests**

Run:

```powershell
cd src-tauri
cargo test
cd ..
```

Expected: the generated Rust crate compiles and tests exit 0.

- [ ] **Step 11: Commit**

```powershell
git add package.json package-lock.json index.html vite.config.ts src src-tauri .gitignore
git commit -m "chore: scaffold Tauri React app"
```

## Task 2: Add Rust Domain Types and Default Presets

**Files:**
- Create: `src-tauri/src/domain/mod.rs`
- Create: `src-tauri/src/domain/activity.rs`
- Create: `src-tauri/src/domain/rules.rs`
- Create: `src-tauri/src/domain/presets.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add Rust dependencies**

Run:

```powershell
cd src-tauri
cargo add chrono --features serde
cargo add serde --features derive
cargo add serde_json
cargo add thiserror
cd ..
```

Expected: `src-tauri/Cargo.toml` and `src-tauri/Cargo.lock` update.

- [ ] **Step 2: Write failing tests for category and rule ordering**

Create `src-tauri/src/domain/rules.rs` with tests first:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ProductivityCategory {
    Productive,
    Unproductive,
    Neutral,
    Ignored,
    Uncategorized,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RuleType {
    Domain,
    App,
    TitleKeyword,
    UrlPattern,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassificationRule {
    pub id: String,
    pub name: String,
    pub rule_type: RuleType,
    pub pattern: String,
    pub category: ProductivityCategory,
    pub priority: i32,
    pub is_builtin: bool,
    pub is_enabled: bool,
}

impl ClassificationRule {
    pub fn specificity(&self) -> i32 {
        match self.rule_type {
            RuleType::UrlPattern => 40,
            RuleType::Domain => 30,
            RuleType::App => 20,
            RuleType::TitleKeyword => 10,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domain_rules_are_more_specific_than_app_rules() {
        let domain = ClassificationRule {
            id: "builtin:domain:docs-google".into(),
            name: "Google Docs".into(),
            rule_type: RuleType::Domain,
            pattern: "docs.google.com".into(),
            category: ProductivityCategory::Productive,
            priority: 0,
            is_builtin: true,
            is_enabled: true,
        };
        let app = ClassificationRule {
            id: "builtin:app:chrome".into(),
            name: "Chrome".into(),
            rule_type: RuleType::App,
            pattern: "chrome.exe".into(),
            category: ProductivityCategory::Neutral,
            priority: 0,
            is_builtin: true,
            is_enabled: true,
        };

        assert!(domain.specificity() > app.specificity());
    }
}
```

- [ ] **Step 3: Run the targeted Rust test**

Run:

```powershell
cd src-tauri
cargo test domain_rules_are_more_specific_than_app_rules
cd ..
```

Expected: PASS.

- [ ] **Step 4: Add activity domain types**

Create `src-tauri/src/domain/activity.rs`:

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::rules::ProductivityCategory;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ActivitySource {
    ActiveWindow,
    BrowserExtension,
    Idle,
    Manual,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivitySession {
    pub id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub duration_seconds: i64,
    pub source: ActivitySource,
    pub app_name: String,
    pub process_name: String,
    pub window_title: String,
    pub domain: Option<String>,
    pub url: Option<String>,
    pub is_idle: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassifiedSession {
    pub session: ActivitySession,
    pub category: ProductivityCategory,
    pub matched_rule_id: Option<String>,
}
```

- [ ] **Step 5: Add broad default presets**

Create `src-tauri/src/domain/presets.rs`:

```rust
use super::rules::{ClassificationRule, ProductivityCategory, RuleType};

fn rule(id: &str, name: &str, rule_type: RuleType, pattern: &str, category: ProductivityCategory, priority: i32) -> ClassificationRule {
    ClassificationRule {
        id: id.to_string(),
        name: name.to_string(),
        rule_type,
        pattern: pattern.to_string(),
        category,
        priority,
        is_builtin: true,
        is_enabled: true,
    }
}

pub fn default_rules() -> Vec<ClassificationRule> {
    let productive_domains = [
        ("chatgpt.com", "ChatGPT"),
        ("chat.openai.com", "ChatGPT Legacy"),
        ("openai.com", "OpenAI"),
        ("platform.openai.com", "OpenAI Platform"),
        ("claude.ai", "Claude"),
        ("github.com", "GitHub"),
        ("gitlab.com", "GitLab"),
        ("stackoverflow.com", "Stack Overflow"),
        ("developer.mozilla.org", "MDN"),
        ("learn.microsoft.com", "Microsoft Learn"),
        ("docs.google.com", "Google Docs"),
        ("notion.so", "Notion"),
        ("figma.com", "Figma"),
        ("linear.app", "Linear"),
        ("atlassian.net", "Atlassian"),
    ];

    let unproductive_domains = [
        ("youtube.com", "YouTube"),
        ("instagram.com", "Instagram"),
        ("tiktok.com", "TikTok"),
        ("x.com", "X"),
        ("twitter.com", "Twitter"),
        ("facebook.com", "Facebook"),
        ("netflix.com", "Netflix"),
        ("disneyplus.com", "Disney+"),
        ("twitch.tv", "Twitch"),
        ("chzzk.naver.com", "Chzzk"),
        ("sooplive.co.kr", "SOOP"),
        ("webtoon.naver.com", "Naver Webtoon"),
        ("comic.naver.com", "Naver Comic"),
    ];

    let neutral_domains = [
        ("google.com", "Google"),
        ("naver.com", "Naver"),
        ("bing.com", "Bing"),
        ("gmail.com", "Gmail"),
        ("mail.google.com", "Google Mail"),
        ("drive.google.com", "Google Drive"),
        ("reddit.com", "Reddit"),
        ("discord.com", "Discord"),
        ("slack.com", "Slack"),
        ("teams.microsoft.com", "Microsoft Teams"),
        ("calendar.google.com", "Google Calendar"),
        ("shopping.naver.com", "Naver Shopping"),
        ("coupang.com", "Coupang"),
    ];

    productive_domains
        .into_iter()
        .map(|(pattern, name)| rule(&format!("builtin:domain:{pattern}"), name, RuleType::Domain, pattern, ProductivityCategory::Productive, 0))
        .chain(unproductive_domains.into_iter().map(|(pattern, name)| rule(&format!("builtin:domain:{pattern}"), name, RuleType::Domain, pattern, ProductivityCategory::Unproductive, 0)))
        .chain(neutral_domains.into_iter().map(|(pattern, name)| rule(&format!("builtin:domain:{pattern}"), name, RuleType::Domain, pattern, ProductivityCategory::Neutral, 0)))
        .collect()
}
```

- [ ] **Step 6: Wire the domain module**

Create `src-tauri/src/domain/mod.rs`:

```rust
pub mod activity;
pub mod presets;
pub mod rules;
```

Add to `src-tauri/src/lib.rs`:

```rust
mod domain;
```

- [ ] **Step 7: Run Rust tests**

Run:

```powershell
cd src-tauri
cargo test
cd ..
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add src-tauri/src/domain src-tauri/src/lib.rs src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "feat: add activity domain and presets"
```

## Task 3: Implement the Classification Engine

**Files:**
- Create: `src-tauri/src/domain/classifier.rs`
- Modify: `src-tauri/src/domain/mod.rs`

- [ ] **Step 1: Write failing classifier tests**

Create `src-tauri/src/domain/classifier.rs`:

```rust
use super::activity::ActivitySession;
use super::rules::{ClassificationRule, ProductivityCategory, RuleType};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassificationResult {
    pub category: ProductivityCategory,
    pub matched_rule_id: Option<String>,
}

pub fn classify(_session: &ActivitySession, _user_rules: &[ClassificationRule], _builtin_rules: &[ClassificationRule]) -> ClassificationResult {
    ClassificationResult {
        category: ProductivityCategory::Uncategorized,
        matched_rule_id: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::activity::ActivitySource;
    use chrono::Utc;

    fn session(domain: Option<&str>, app: &str, title: &str) -> ActivitySession {
        ActivitySession {
            id: "s1".into(),
            started_at: Utc::now(),
            ended_at: Utc::now(),
            duration_seconds: 60,
            source: ActivitySource::ActiveWindow,
            app_name: app.into(),
            process_name: app.into(),
            window_title: title.into(),
            domain: domain.map(str::to_string),
            url: None,
            is_idle: false,
        }
    }

    fn rule(id: &str, rule_type: RuleType, pattern: &str, category: ProductivityCategory, is_builtin: bool) -> ClassificationRule {
        ClassificationRule {
            id: id.into(),
            name: id.into(),
            rule_type,
            pattern: pattern.into(),
            category,
            priority: 0,
            is_builtin,
            is_enabled: true,
        }
    }

    #[test]
    fn user_rules_override_builtin_rules() {
        let user_rule = rule("user:youtube", RuleType::Domain, "youtube.com", ProductivityCategory::Productive, false);
        let builtin_rule = rule("builtin:youtube", RuleType::Domain, "youtube.com", ProductivityCategory::Unproductive, true);

        let result = classify(&session(Some("youtube.com"), "chrome.exe", "Lecture - YouTube"), &[user_rule], &[builtin_rule]);

        assert_eq!(result.category, ProductivityCategory::Productive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("user:youtube"));
    }

    #[test]
    fn subdomains_beat_parent_domains() {
        let parent = rule("builtin:naver", RuleType::Domain, "naver.com", ProductivityCategory::Neutral, true);
        let child = rule("builtin:chzzk", RuleType::Domain, "chzzk.naver.com", ProductivityCategory::Unproductive, true);

        let result = classify(&session(Some("chzzk.naver.com"), "chrome.exe", "Chzzk"), &[], &[parent, child]);

        assert_eq!(result.category, ProductivityCategory::Unproductive);
        assert_eq!(result.matched_rule_id.as_deref(), Some("builtin:chzzk"));
    }

    #[test]
    fn title_keyword_matches_when_domain_is_missing() {
        let keyword = rule("builtin:title:chatgpt", RuleType::TitleKeyword, "ChatGPT", ProductivityCategory::Productive, true);

        let result = classify(&session(None, "chrome.exe", "ChatGPT - Google Chrome"), &[], &[keyword]);

        assert_eq!(result.category, ProductivityCategory::Productive);
    }
}
```

- [ ] **Step 2: Run classifier tests to verify failure**

Run:

```powershell
cd src-tauri
cargo test domain::classifier
cd ..
```

Expected: at least one test fails because `classify` always returns uncategorized.

- [ ] **Step 3: Implement classifier matching**

Replace the body in `src-tauri/src/domain/classifier.rs` with:

```rust
use super::activity::ActivitySession;
use super::rules::{ClassificationRule, ProductivityCategory, RuleType};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassificationResult {
    pub category: ProductivityCategory,
    pub matched_rule_id: Option<String>,
}

pub fn classify(session: &ActivitySession, user_rules: &[ClassificationRule], builtin_rules: &[ClassificationRule]) -> ClassificationResult {
    user_rules
        .iter()
        .filter(|rule| rule.is_enabled)
        .filter(|rule| matches_rule(rule, session))
        .max_by_key(|rule| (rule.specificity(), rule.priority, rule.pattern.len() as i32))
        .or_else(|| {
            builtin_rules
                .iter()
                .filter(|rule| rule.is_enabled)
                .filter(|rule| matches_rule(rule, session))
                .max_by_key(|rule| (rule.specificity(), rule.priority, rule.pattern.len() as i32))
        })
        .map(|rule| ClassificationResult {
            category: rule.category,
            matched_rule_id: Some(rule.id.clone()),
        })
        .unwrap_or(ClassificationResult {
            category: ProductivityCategory::Uncategorized,
            matched_rule_id: None,
        })
}

fn matches_rule(rule: &ClassificationRule, session: &ActivitySession) -> bool {
    match rule.rule_type {
        RuleType::Domain => session
            .domain
            .as_deref()
            .map(|domain| domain == rule.pattern || domain.ends_with(&format!(".{}", rule.pattern)))
            .unwrap_or(false),
        RuleType::App => {
            session.process_name.eq_ignore_ascii_case(&rule.pattern)
                || session.app_name.eq_ignore_ascii_case(&rule.pattern)
        }
        RuleType::TitleKeyword => session
            .window_title
            .to_lowercase()
            .contains(&rule.pattern.to_lowercase()),
        RuleType::UrlPattern => session
            .url
            .as_deref()
            .map(|url| url.contains(&rule.pattern))
            .unwrap_or(false),
    }
}
```

Keep the tests from Step 1 at the bottom of the file.

- [ ] **Step 4: Register the module**

Update `src-tauri/src/domain/mod.rs`:

```rust
pub mod activity;
pub mod classifier;
pub mod presets;
pub mod rules;
```

- [ ] **Step 5: Run classifier tests**

Run:

```powershell
cd src-tauri
cargo test domain::classifier
cd ..
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add src-tauri/src/domain
git commit -m "feat: classify activity sessions"
```

## Task 4: Add SQLite Schema and Repository Layer

**Files:**
- Create: `src-tauri/src/storage/mod.rs`
- Create: `src-tauri/src/storage/schema.rs`
- Create: `src-tauri/src/storage/repository.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add storage dependencies**

Run:

```powershell
cd src-tauri
cargo add rusqlite --features bundled,chrono
cargo add uuid --features v4,serde
cd ..
```

Expected: SQLite can be compiled without requiring a system SQLite install.

- [ ] **Step 2: Write schema creation test**

Create `src-tauri/src/storage/schema.rs`:

```rust
use rusqlite::Connection;

pub fn initialize_schema(_conn: &Connection) -> rusqlite::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_activity_sessions_table() {
        let conn = Connection::open_in_memory().expect("in-memory db");
        initialize_schema(&conn).expect("schema initialized");

        let exists: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='activity_sessions'",
                [],
                |row| row.get(0),
            )
            .expect("table count");

        assert_eq!(exists, 1);
    }
}
```

- [ ] **Step 3: Run schema test to verify failure**

Run:

```powershell
cd src-tauri
cargo test storage::schema::tests::creates_activity_sessions_table
cd ..
```

Expected: FAIL because `activity_sessions` is not created.

- [ ] **Step 4: Implement schema creation**

Replace `initialize_schema`:

```rust
pub fn initialize_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS activity_sessions (
          id TEXT PRIMARY KEY,
          started_at TEXT NOT NULL,
          ended_at TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          source TEXT NOT NULL,
          app_name TEXT NOT NULL,
          process_name TEXT NOT NULL,
          window_title TEXT NOT NULL,
          domain TEXT,
          url TEXT,
          url_storage_mode TEXT NOT NULL DEFAULT 'domain',
          is_idle INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS classification_rules (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          rule_type TEXT NOT NULL,
          pattern TEXT NOT NULL,
          category TEXT NOT NULL,
          priority INTEGER NOT NULL DEFAULT 0,
          is_builtin INTEGER NOT NULL DEFAULT 0,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS classification_results (
          session_id TEXT PRIMARY KEY,
          rule_id TEXT,
          category TEXT NOT NULL,
          confidence REAL NOT NULL DEFAULT 1.0,
          classified_at TEXT NOT NULL,
          FOREIGN KEY(session_id) REFERENCES activity_sessions(id) ON DELETE CASCADE,
          FOREIGN KEY(rule_id) REFERENCES classification_rules(id) ON DELETE SET NULL
        );

        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS browser_events (
          id TEXT PRIMARY KEY,
          occurred_at TEXT NOT NULL,
          domain TEXT NOT NULL,
          url TEXT,
          title TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON activity_sessions(started_at);
        CREATE INDEX IF NOT EXISTS idx_sessions_domain ON activity_sessions(domain);
        CREATE INDEX IF NOT EXISTS idx_rules_type_pattern ON classification_rules(rule_type, pattern);
        "#,
    )
}
```

- [ ] **Step 5: Run schema test**

Run:

```powershell
cd src-tauri
cargo test storage::schema
cd ..
```

Expected: PASS.

- [ ] **Step 6: Create repository save/list tests**

Create `src-tauri/src/storage/repository.rs`:

```rust
use chrono::Utc;
use rusqlite::{params, Connection};

use crate::domain::activity::{ActivitySession, ActivitySource};
use crate::storage::schema::initialize_schema;

pub struct Repository {
    conn: Connection,
}

impl Repository {
    pub fn in_memory_for_test() -> rusqlite::Result<Self> {
        let conn = Connection::open_in_memory()?;
        initialize_schema(&conn)?;
        Ok(Self { conn })
    }

    pub fn save_session(&self, _session: &ActivitySession) -> rusqlite::Result<()> {
        Ok(())
    }

    pub fn list_sessions_for_day(&self, _date: chrono::NaiveDate) -> rusqlite::Result<Vec<ActivitySession>> {
        Ok(Vec::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn saves_and_lists_sessions_for_day() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let started_at = Utc::now();
        let session = ActivitySession {
            id: "session-1".into(),
            started_at,
            ended_at: started_at + chrono::Duration::minutes(5),
            duration_seconds: 300,
            source: ActivitySource::ActiveWindow,
            app_name: "Chrome".into(),
            process_name: "chrome.exe".into(),
            window_title: "ChatGPT".into(),
            domain: Some("chatgpt.com".into()),
            url: None,
            is_idle: false,
        };

        repo.save_session(&session).expect("saved");
        let rows = repo.list_sessions_for_day(started_at.date_naive()).expect("rows");

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].domain.as_deref(), Some("chatgpt.com"));
    }
}
```

- [ ] **Step 7: Run repository test to verify failure**

Run:

```powershell
cd src-tauri
cargo test storage::repository::tests::saves_and_lists_sessions_for_day
cd ..
```

Expected: FAIL because `save_session` does not persist.

- [ ] **Step 8: Implement repository persistence**

Replace the repository methods with:

```rust
    pub fn save_session(&self, session: &ActivitySession) -> rusqlite::Result<()> {
        self.conn.execute(
            r#"
            INSERT OR REPLACE INTO activity_sessions (
              id, started_at, ended_at, duration_seconds, source, app_name, process_name,
              window_title, domain, url, url_storage_mode, is_idle, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'domain', ?11, ?12)
            "#,
            params![
                &session.id,
                session.started_at.to_rfc3339(),
                session.ended_at.to_rfc3339(),
                session.duration_seconds,
                format!("{:?}", session.source),
                &session.app_name,
                &session.process_name,
                &session.window_title,
                session.domain.as_deref(),
                session.url.as_deref(),
                if session.is_idle { 1 } else { 0 },
                Utc::now().to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn list_sessions_for_day(&self, date: chrono::NaiveDate) -> rusqlite::Result<Vec<ActivitySession>> {
        let start = date.and_hms_opt(0, 0, 0).unwrap().and_utc();
        let end = start + chrono::Duration::days(1);
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, started_at, ended_at, duration_seconds, app_name, process_name,
                   window_title, domain, url, is_idle
            FROM activity_sessions
            WHERE started_at >= ?1 AND started_at < ?2
            ORDER BY started_at ASC
            "#,
        )?;

        let rows = stmt.query_map(params![start.to_rfc3339(), end.to_rfc3339()], |row| {
            let started_at: String = row.get(1)?;
            let ended_at: String = row.get(2)?;
            Ok(ActivitySession {
                id: row.get(0)?,
                started_at: chrono::DateTime::parse_from_rfc3339(&started_at).unwrap().with_timezone(&Utc),
                ended_at: chrono::DateTime::parse_from_rfc3339(&ended_at).unwrap().with_timezone(&Utc),
                duration_seconds: row.get(3)?,
                source: ActivitySource::ActiveWindow,
                app_name: row.get(4)?,
                process_name: row.get(5)?,
                window_title: row.get(6)?,
                domain: row.get(7)?,
                url: row.get(8)?,
                is_idle: row.get::<_, i64>(9)? == 1,
            })
        })?;

        rows.collect()
    }
```

- [ ] **Step 9: Register storage module**

Create `src-tauri/src/storage/mod.rs`:

```rust
pub mod repository;
pub mod schema;
```

Add to `src-tauri/src/lib.rs`:

```rust
mod storage;
```

- [ ] **Step 10: Run storage tests**

Run:

```powershell
cd src-tauri
cargo test storage
cd ..
```

Expected: PASS.

- [ ] **Step 11: Commit**

```powershell
git add src-tauri/src/storage src-tauri/src/lib.rs src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "feat: persist activity sessions"
```

## Task 5: Add Session Merging and Collector Abstractions

**Files:**
- Create: `src-tauri/src/collector/mod.rs`
- Create: `src-tauri/src/collector/session_merger.rs`
- Create: `src-tauri/src/collector/active_window.rs`
- Create: `src-tauri/src/collector/idle.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write session merger tests**

Create `src-tauri/src/collector/session_merger.rs`:

```rust
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivitySample {
    pub observed_at: DateTime<Utc>,
    pub app_name: String,
    pub process_name: String,
    pub window_title: String,
    pub domain: Option<String>,
    pub is_idle: bool,
}

pub fn should_merge(_current: &ActivitySample, _next: &ActivitySample) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn sample(title: &str, domain: Option<&str>, is_idle: bool) -> ActivitySample {
        ActivitySample {
            observed_at: Utc::now(),
            app_name: "Chrome".into(),
            process_name: "chrome.exe".into(),
            window_title: title.into(),
            domain: domain.map(str::to_string),
            is_idle,
        }
    }

    #[test]
    fn merges_same_domain_title_and_idle_state() {
        assert!(should_merge(
            &sample("ChatGPT", Some("chatgpt.com"), false),
            &sample("ChatGPT", Some("chatgpt.com"), false)
        ));
    }

    #[test]
    fn splits_when_idle_state_changes() {
        assert!(!should_merge(
            &sample("ChatGPT", Some("chatgpt.com"), false),
            &sample("ChatGPT", Some("chatgpt.com"), true)
        ));
    }
}
```

- [ ] **Step 2: Run merger tests to verify failure**

Run:

```powershell
cd src-tauri
cargo test collector::session_merger
cd ..
```

Expected: FAIL because identical samples do not merge.

- [ ] **Step 3: Implement session merge predicate**

Replace `should_merge`:

```rust
pub fn should_merge(current: &ActivitySample, next: &ActivitySample) -> bool {
    current.app_name == next.app_name
        && current.process_name == next.process_name
        && current.window_title == next.window_title
        && current.domain == next.domain
        && current.is_idle == next.is_idle
}
```

- [ ] **Step 4: Add collector traits**

Create `src-tauri/src/collector/active_window.rs`:

```rust
use crate::collector::session_merger::ActivitySample;

pub trait ActiveWindowReader: Send + Sync {
    fn read_active_window(&self) -> anyhow::Result<ActivitySample>;
}
```

Create `src-tauri/src/collector/idle.rs`:

```rust
pub trait IdleReader: Send + Sync {
    fn is_idle(&self) -> anyhow::Result<bool>;
}
```

- [ ] **Step 5: Add `anyhow` dependency**

Run:

```powershell
cd src-tauri
cargo add anyhow
cd ..
```

- [ ] **Step 6: Register collector module**

Create `src-tauri/src/collector/mod.rs`:

```rust
pub mod active_window;
pub mod idle;
pub mod session_merger;
```

Add to `src-tauri/src/lib.rs`:

```rust
mod collector;
```

- [ ] **Step 7: Run collector tests**

Run:

```powershell
cd src-tauri
cargo test collector
cd ..
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add src-tauri/src/collector src-tauri/src/lib.rs src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "feat: add collector abstractions"
```

## Task 6: Add Windows Active Window and Idle Readers

**Files:**
- Modify: `src-tauri/src/collector/active_window.rs`
- Modify: `src-tauri/src/collector/idle.rs`

- [ ] **Step 1: Add Windows API dependency**

Run:

```powershell
cd src-tauri
cargo add windows --features Win32_Foundation,Win32_UI_WindowsAndMessaging,Win32_System_Threading,Win32_System_ProcessStatus,Win32_System_SystemInformation,Win32_UI_Input_KeyboardAndMouse
cd ..
```

Expected: `windows` crate is added with the required Win32 feature gates.

- [ ] **Step 2: Implement Windows idle reader**

Append to `src-tauri/src/collector/idle.rs`:

```rust
#[cfg(target_os = "windows")]
pub struct WindowsIdleReader {
    pub idle_threshold_seconds: u32,
}

#[cfg(target_os = "windows")]
impl IdleReader for WindowsIdleReader {
    fn is_idle(&self) -> anyhow::Result<bool> {
        use windows::Win32::System::SystemInformation::GetTickCount;
        use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};

        unsafe {
            let mut info = LASTINPUTINFO {
                cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
                dwTime: 0,
            };
            GetLastInputInfo(&mut info)?;
            let now = GetTickCount();
            let idle_ms = now - info.dwTime;
            Ok(idle_ms / 1000 >= self.idle_threshold_seconds)
        }
    }
}
```

- [ ] **Step 3: Implement Windows active-window reader**

Append to `src-tauri/src/collector/active_window.rs`:

```rust
#[cfg(target_os = "windows")]
pub struct WindowsActiveWindowReader;

#[cfg(target_os = "windows")]
impl ActiveWindowReader for WindowsActiveWindowReader {
    fn read_active_window(&self) -> anyhow::Result<ActivitySample> {
        use chrono::Utc;
        use windows::Win32::Foundation::{CloseHandle, HWND};
        use windows::Win32::System::ProcessStatus::K32GetModuleBaseNameW;
        use windows::Win32::System::Threading::{OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_VM_READ};
        use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId};

        unsafe {
            let hwnd: HWND = GetForegroundWindow();
            let title_len = GetWindowTextLengthW(hwnd);
            let mut title_buf = vec![0u16; title_len as usize + 1];
            let copied = GetWindowTextW(hwnd, &mut title_buf);
            let window_title = String::from_utf16_lossy(&title_buf[..copied as usize]);

            let mut pid = 0u32;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, false, pid)?;
            let mut process_buf = vec![0u16; 260];
            let process_len = K32GetModuleBaseNameW(process, None, &mut process_buf);
            let process_name = String::from_utf16_lossy(&process_buf[..process_len as usize]);
            CloseHandle(process)?;

            Ok(ActivitySample {
                observed_at: Utc::now(),
                app_name: process_name.clone(),
                process_name,
                window_title,
                domain: None,
                is_idle: false,
            })
        }
    }
}
```

- [ ] **Step 4: Compile on Windows**

Run:

```powershell
cd src-tauri
cargo check
cd ..
```

Expected: PASS on Windows.

- [ ] **Step 5: Run all Rust tests**

Run:

```powershell
cd src-tauri
cargo test
cd ..
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add src-tauri/src/collector src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "feat: read Windows activity signals"
```

## Task 7: Add Tauri Commands, App State, and Dev Data

**Files:**
- Create: `src-tauri/src/app_state.rs`
- Create: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs`
- Create: `src/types/activity.ts`
- Create: `src/api/activityApi.ts`

- [ ] **Step 1: Define frontend DTOs**

Create `src/types/activity.ts`:

```ts
export type ProductivityCategory =
  | "productive"
  | "unproductive"
  | "neutral"
  | "ignored"
  | "uncategorized";

export interface ActivitySession {
  id: string;
  startedAt: string;
  endedAt: string;
  durationSeconds: number;
  appName: string;
  processName: string;
  windowTitle: string;
  domain?: string;
  isIdle: boolean;
  category: ProductivityCategory;
  matchedRuleId?: string;
}

export interface TodaySummary {
  trackedSeconds: number;
  productiveSeconds: number;
  unproductiveSeconds: number;
  neutralSeconds: number;
  idleSeconds: number;
  uncategorizedSeconds: number;
}
```

- [ ] **Step 2: Add dev API fallback**

Create `src/api/activityApi.ts`:

```ts
import { invoke } from "@tauri-apps/api/core";
import type { ActivitySession, TodaySummary } from "../types/activity";

const devSessions: ActivitySession[] = [
  {
    id: "dev-1",
    startedAt: new Date().toISOString(),
    endedAt: new Date(Date.now() + 45 * 60 * 1000).toISOString(),
    durationSeconds: 2700,
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "ChatGPT",
    domain: "chatgpt.com",
    isIdle: false,
    category: "productive",
    matchedRuleId: "builtin:domain:chatgpt.com",
  },
  {
    id: "dev-2",
    startedAt: new Date(Date.now() + 46 * 60 * 1000).toISOString(),
    endedAt: new Date(Date.now() + 76 * 60 * 1000).toISOString(),
    durationSeconds: 1800,
    appName: "Chrome",
    processName: "chrome.exe",
    windowTitle: "YouTube",
    domain: "youtube.com",
    isIdle: false,
    category: "unproductive",
    matchedRuleId: "builtin:domain:youtube.com",
  },
];

export async function getTodaySummary(): Promise<TodaySummary> {
  if (!("__TAURI_INTERNALS__" in window)) {
    return {
      trackedSeconds: 4500,
      productiveSeconds: 2700,
      unproductiveSeconds: 1800,
      neutralSeconds: 0,
      idleSeconds: 0,
      uncategorizedSeconds: 0,
    };
  }
  return invoke<TodaySummary>("get_today_summary");
}

export async function getTodaySessions(): Promise<ActivitySession[]> {
  if (!("__TAURI_INTERNALS__" in window)) {
    return devSessions;
  }
  return invoke<ActivitySession[]>("get_today_sessions");
}
```

- [ ] **Step 3: Add Rust app state**

Create `src-tauri/src/app_state.rs`:

```rust
use std::sync::{Arc, Mutex};

use crate::storage::repository::Repository;

pub struct AppState {
    pub repository: Arc<Mutex<Repository>>,
}
```

- [ ] **Step 4: Add Tauri command stubs**

Create `src-tauri/src/commands.rs`:

```rust
use serde::Serialize;
use tauri::State;

use crate::app_state::AppState;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodaySummaryDto {
    pub tracked_seconds: i64,
    pub productive_seconds: i64,
    pub unproductive_seconds: i64,
    pub neutral_seconds: i64,
    pub idle_seconds: i64,
    pub uncategorized_seconds: i64,
}

#[tauri::command]
pub fn get_today_summary(_state: State<AppState>) -> TodaySummaryDto {
    TodaySummaryDto {
        tracked_seconds: 0,
        productive_seconds: 0,
        unproductive_seconds: 0,
        neutral_seconds: 0,
        idle_seconds: 0,
        uncategorized_seconds: 0,
    }
}

#[tauri::command]
pub fn get_today_sessions(_state: State<AppState>) -> Vec<serde_json::Value> {
    Vec::new()
}
```

- [ ] **Step 5: Wire modules and commands**

Update `src-tauri/src/lib.rs` so the builder registers state and commands:

```rust
mod app_state;
mod collector;
mod commands;
mod domain;
mod storage;

use app_state::AppState;
use storage::repository::Repository;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let repository = std::sync::Arc::new(std::sync::Mutex::new(
        Repository::open_default().expect("repository opens"),
    ));

    tauri::Builder::default()
        .manage(AppState {
            repository,
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_today_summary,
            commands::get_today_sessions
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 6: Add `Repository::open_default`**

Add to `src-tauri/src/storage/repository.rs`:

```rust
    pub fn open_default() -> rusqlite::Result<Self> {
        let data_dir = std::env::current_dir().unwrap().join("time-manager.sqlite3");
        let conn = Connection::open(data_dir)?;
        initialize_schema(&conn)?;
        Ok(Self { conn })
    }
```

- [ ] **Step 7: Run frontend and Rust checks**

Run:

```powershell
npm test
cd src-tauri
cargo test
cargo check
cd ..
```

Expected: all commands exit 0.

- [ ] **Step 8: Commit**

```powershell
git add src src-tauri
git commit -m "feat: expose activity commands"
```

## Task 8: Build the Colorful Dashboard Charts and Tables

**Files:**
- Create: `src/lib/time.ts`
- Create: `src/lib/colors.ts`
- Create: `src/components/layout/AppShell.tsx`
- Create: `src/components/dashboard/TodaySummary.tsx`
- Create: `src/components/dashboard/DayTimeline.tsx`
- Create: `src/components/dashboard/WeeklyTrends.tsx`
- Create: `src/components/tables/UsageTable.tsx`
- Modify: `src/App.tsx`
- Modify: `src/App.test.tsx`
- Modify: `src/styles.css`

- [ ] **Step 1: Write helper tests**

Create `src/lib/time.test.ts`:

```ts
import { formatDuration } from "./time";

describe("formatDuration", () => {
  it("formats hours and minutes", () => {
    expect(formatDuration(3660)).toBe("1h 1m");
  });

  it("formats minutes only", () => {
    expect(formatDuration(1800)).toBe("30m");
  });
});
```

- [ ] **Step 2: Run helper test to verify failure**

Run:

```powershell
npm test -- src/lib/time.test.ts
```

Expected: FAIL because `src/lib/time.ts` does not exist.

- [ ] **Step 3: Implement time helper**

Create `src/lib/time.ts`:

```ts
export function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
}
```

- [ ] **Step 4: Add color helper**

Create `src/lib/colors.ts`:

```ts
import type { ProductivityCategory } from "../types/activity";

export const categoryColors: Record<ProductivityCategory, string> = {
  productive: "#16a34a",
  unproductive: "#ef4444",
  neutral: "#2563eb",
  ignored: "#6b7280",
  uncategorized: "#8b5cf6",
};

export const idleColor = "#f59e0b";

export function colorForName(name: string): string {
  const palette = ["#0ea5e9", "#22c55e", "#f97316", "#a855f7", "#eab308", "#14b8a6", "#f43f5e"];
  const hash = Array.from(name).reduce((acc, char) => acc + char.charCodeAt(0), 0);
  return palette[hash % palette.length];
}
```

- [ ] **Step 5: Create dashboard components**

Create `src/components/dashboard/TodaySummary.tsx`:

```tsx
import { Pie, PieChart, Cell, ResponsiveContainer, BarChart, Bar, XAxis, Tooltip } from "recharts";
import type { TodaySummary as TodaySummaryData } from "../../types/activity";
import { formatDuration } from "../../lib/time";

const slices = [
  ["Productive", "productiveSeconds", "#16a34a"],
  ["Unproductive", "unproductiveSeconds", "#ef4444"],
  ["Neutral", "neutralSeconds", "#2563eb"],
  ["Idle", "idleSeconds", "#f59e0b"],
  ["Uncategorized", "uncategorizedSeconds", "#8b5cf6"],
] as const;

export function TodaySummary({ summary }: { summary: TodaySummaryData }) {
  const data = slices.map(([name, key, color]) => ({ name, value: summary[key], color }));
  const ratio = summary.trackedSeconds === 0 ? 0 : Math.round((summary.productiveSeconds / summary.trackedSeconds) * 100);

  return (
    <section className="dashboard-section" aria-labelledby="today-summary-heading">
      <div className="section-heading">
        <h2 id="today-summary-heading">Today</h2>
        <span>{ratio}% productive</span>
      </div>
      <div className="summary-grid">
        {data.map((item) => (
          <article className="metric-card" key={item.name}>
            <span className="metric-dot" style={{ background: item.color }} />
            <p>{item.name}</p>
            <strong>{formatDuration(item.value)}</strong>
          </article>
        ))}
        <div className="chart-panel">
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={data} dataKey="value" innerRadius={58} outerRadius={86}>
                {data.map((entry) => <Cell key={entry.name} fill={entry.color} />)}
              </Pie>
            </PieChart>
          </ResponsiveContainer>
        </div>
        <div className="chart-panel">
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={data}>
              <XAxis dataKey="name" hide />
              <Tooltip />
              <Bar dataKey="value">
                {data.map((entry) => <Cell key={entry.name} fill={entry.color} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </section>
  );
}
```

Create `src/components/dashboard/DayTimeline.tsx`:

```tsx
import type { ActivitySession } from "../../types/activity";
import { categoryColors, idleColor } from "../../lib/colors";
import { formatDuration } from "../../lib/time";

export function DayTimeline({ sessions }: { sessions: ActivitySession[] }) {
  const total = sessions.reduce((sum, session) => sum + session.durationSeconds, 0);

  return (
    <section className="dashboard-section" aria-labelledby="timeline-heading">
      <div className="section-heading">
        <h2 id="timeline-heading">Timeline</h2>
        <span>{sessions.length} segments</span>
      </div>
      <div className="timeline-panel">
        <div className="timeline-track" role="list" aria-label="Today activity timeline">
          {sessions.map((session) => {
            const width = total === 0 ? 0 : Math.max(3, (session.durationSeconds / total) * 100);
            const color = session.isIdle ? idleColor : categoryColors[session.category];
            return (
              <button
                className="timeline-segment"
                key={session.id}
                style={{ width: `${width}%`, background: color }}
                title={`${session.domain ?? session.appName} - ${formatDuration(session.durationSeconds)}`}
                aria-label={`${session.domain ?? session.appName}, ${formatDuration(session.durationSeconds)}`}
              />
            );
          })}
        </div>
      </div>
    </section>
  );
}
```

Create `src/components/tables/UsageTable.tsx`:

```tsx
import type { ActivitySession } from "../../types/activity";
import { formatDuration } from "../../lib/time";

interface Row {
  name: string;
  category: string;
  durationSeconds: number;
  percent: number;
  matchedRuleId?: string;
}

function buildRows(sessions: ActivitySession[]): Row[] {
  const total = sessions.reduce((sum, session) => sum + session.durationSeconds, 0);
  const grouped = new Map<string, Row>();

  for (const session of sessions) {
    const name = session.domain ?? session.appName;
    const current = grouped.get(name) ?? {
      name,
      category: session.category,
      durationSeconds: 0,
      percent: 0,
      matchedRuleId: session.matchedRuleId,
    };
    current.durationSeconds += session.durationSeconds;
    current.percent = total === 0 ? 0 : Math.round((current.durationSeconds / total) * 100);
    grouped.set(name, current);
  }

  return Array.from(grouped.values()).sort((a, b) => b.durationSeconds - a.durationSeconds);
}

export function UsageTable({ title, sessions }: { title: string; sessions: ActivitySession[] }) {
  const rows = buildRows(sessions);

  return (
    <section className="dashboard-section" aria-labelledby="usage-heading">
      <div className="section-heading">
        <h2 id="usage-heading">{title}</h2>
        <span>{rows.length} rows</span>
      </div>
      <div className="table-panel">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Category</th>
              <th>Duration</th>
              <th>Share</th>
              <th>Matched rule</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.name}>
                <td>{row.name}</td>
                <td>{row.category}</td>
                <td>{formatDuration(row.durationSeconds)}</td>
                <td>{row.percent}%</td>
                <td>{row.matchedRuleId ?? "None"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
```

Create `src/components/dashboard/WeeklyTrends.tsx`:

```tsx
import { Bar, BarChart, CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { ActivitySession } from "../../types/activity";

export function WeeklyTrends({ sessions }: { sessions: ActivitySession[] }) {
  const today = new Date().toLocaleDateString(undefined, { weekday: "short" });
  const productive = sessions.filter((session) => session.category === "productive").reduce((sum, session) => sum + session.durationSeconds, 0);
  const unproductive = sessions.filter((session) => session.category === "unproductive").reduce((sum, session) => sum + session.durationSeconds, 0);
  const neutral = sessions.filter((session) => session.category === "neutral").reduce((sum, session) => sum + session.durationSeconds, 0);
  const ratio = productive + unproductive + neutral === 0 ? 0 : Math.round((productive / (productive + unproductive + neutral)) * 100);
  const data = [{ day: today, productive, unproductive, neutral, ratio }];

  return (
    <section className="dashboard-section" aria-labelledby="weekly-heading">
      <div className="section-heading">
        <h2 id="weekly-heading">Weekly Trends</h2>
        <span>{ratio}% productive today</span>
      </div>
      <div className="weekly-grid">
        <div className="chart-panel">
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={data}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="day" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Bar dataKey="productive" stackId="time" fill="#16a34a" />
              <Bar dataKey="unproductive" stackId="time" fill="#ef4444" />
              <Bar dataKey="neutral" stackId="time" fill="#2563eb" />
            </BarChart>
          </ResponsiveContainer>
        </div>
        <div className="chart-panel">
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="day" />
              <YAxis domain={[0, 100]} />
              <Tooltip />
              <Line type="monotone" dataKey="ratio" stroke="#16a34a" strokeWidth={3} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 6: Compose `App.tsx`**

```tsx
import { useEffect, useState } from "react";
import { getTodaySessions, getTodaySummary } from "./api/activityApi";
import { TodaySummary } from "./components/dashboard/TodaySummary";
import { DayTimeline } from "./components/dashboard/DayTimeline";
import { WeeklyTrends } from "./components/dashboard/WeeklyTrends";
import { UsageTable } from "./components/tables/UsageTable";
import type { ActivitySession, TodaySummary as TodaySummaryData } from "./types/activity";
import "./styles.css";

export default function App() {
  const [summary, setSummary] = useState<TodaySummaryData | null>(null);
  const [sessions, setSessions] = useState<ActivitySession[]>([]);

  useEffect(() => {
    void Promise.all([getTodaySummary(), getTodaySessions()]).then(([nextSummary, nextSessions]) => {
      setSummary(nextSummary);
      setSessions(nextSessions);
    });
  }, []);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <h1>Time Manager</h1>
          <p>Local automatic activity analytics</p>
        </div>
        <span className="status-pill">Tracking</span>
      </header>
      {summary && <TodaySummary summary={summary} />}
      <DayTimeline sessions={sessions} />
      <UsageTable title="Top apps and sites" sessions={sessions} />
      <WeeklyTrends sessions={sessions} />
    </main>
  );
}
```

- [ ] **Step 7: Update app test**

Update `src/App.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import App from "./App";

describe("App", () => {
  it("renders dashboard charts and tables", async () => {
    render(<App />);

    expect(screen.getByRole("heading", { name: /time manager/i })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: /today/i })).toBeInTheDocument();
    expect(await screen.findByText(/top apps and sites/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 8: Add dense colorful CSS**

Update `src/styles.css` with responsive dashboard layout, no nested cards:

```css
:root {
  color: #172033;
  background: #f7f8fb;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

body {
  margin: 0;
  min-width: 320px;
  min-height: 100vh;
  background: #f7f8fb;
}

.app-shell {
  max-width: 1440px;
  margin: 0 auto;
  padding: 24px;
}

.topbar,
.dashboard-section {
  margin-bottom: 20px;
}

.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.topbar h1,
.section-heading h2 {
  margin: 0;
  letter-spacing: 0;
}

.status-pill {
  border: 1px solid #bbf7d0;
  color: #166534;
  background: #dcfce7;
  border-radius: 999px;
  padding: 6px 12px;
  font-size: 13px;
}

.section-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 12px;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(128px, 1fr));
  gap: 12px;
}

.metric-card,
.chart-panel,
.table-panel,
.timeline-panel {
  background: #ffffff;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
}

.metric-card {
  padding: 14px;
}

.metric-card p {
  margin: 8px 0 4px;
  color: #64748b;
}

.metric-card strong {
  font-size: 22px;
}

.metric-dot {
  display: block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
}

.chart-panel {
  grid-column: span 2;
  min-height: 240px;
  padding: 12px;
}

.weekly-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

.timeline-panel {
  padding: 14px;
}

.timeline-track {
  display: flex;
  width: 100%;
  height: 42px;
  overflow: hidden;
  border-radius: 8px;
  background: #e5e7eb;
}

.timeline-segment {
  height: 42px;
  min-width: 3px;
  border: 0;
  cursor: pointer;
}

.timeline-segment:focus-visible {
  outline: 3px solid #111827;
  outline-offset: -3px;
}

.table-panel {
  overflow-x: auto;
}

table {
  width: 100%;
  border-collapse: collapse;
  min-width: 720px;
}

th,
td {
  padding: 12px;
  border-bottom: 1px solid #e5e7eb;
  text-align: left;
  white-space: nowrap;
}

th {
  color: #475569;
  font-size: 12px;
  text-transform: uppercase;
}

.rule-form {
  display: grid;
  grid-template-columns: 160px minmax(220px, 1fr) 160px auto;
  gap: 10px;
  margin-bottom: 12px;
}

input,
select,
button {
  min-height: 38px;
  border-radius: 8px;
  border: 1px solid #cbd5e1;
  background: #ffffff;
  color: #172033;
}

button {
  padding: 0 14px;
  cursor: pointer;
  font-weight: 600;
}

@media (max-width: 960px) {
  .summary-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .chart-panel {
    grid-column: span 2;
  }

  .weekly-grid,
  .rule-form {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 560px) {
  .app-shell {
    padding: 16px;
  }

  .summary-grid {
    grid-template-columns: 1fr;
  }

  .chart-panel {
    grid-column: span 1;
  }
}
```

- [ ] **Step 9: Run frontend tests and build**

Run:

```powershell
npm test
npm run build
```

Expected: PASS and Vite build succeeds.

- [ ] **Step 10: Commit**

```powershell
git add src package.json package-lock.json
git commit -m "feat: build analytics dashboard"
```

## Task 9: Implement Rules Settings and Uncategorized Review

**Files:**
- Create: `src/components/rules/RulesSettings.tsx`
- Create: `src/components/rules/UncategorizedReview.tsx`
- Modify: `src/types/activity.ts`
- Modify: `src/api/activityApi.ts`
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/storage/repository.rs`
- Modify: `src/App.tsx`

- [ ] **Step 1: Add rule DTOs**

Append to `src/types/activity.ts`:

```ts
export type RuleType = "domain" | "app" | "titleKeyword" | "urlPattern";

export interface ClassificationRule {
  id: string;
  name: string;
  ruleType: RuleType;
  pattern: string;
  category: ProductivityCategory;
  priority: number;
  isBuiltin: boolean;
  isEnabled: boolean;
}

export interface RuleDraft {
  name: string;
  ruleType: RuleType;
  pattern: string;
  category: ProductivityCategory;
}
```

- [ ] **Step 2: Add API wrappers**

Update the existing type import in `src/api/activityApi.ts`:

```ts
import type { ActivitySession, ClassificationRule, RuleDraft, TodaySummary } from "../types/activity";
```

Then append the API functions:

```ts

export async function listRules(): Promise<ClassificationRule[]> {
  if (!("__TAURI_INTERNALS__" in window)) {
    return [
      {
        id: "builtin:domain:chatgpt.com",
        name: "ChatGPT",
        ruleType: "domain",
        pattern: "chatgpt.com",
        category: "productive",
        priority: 0,
        isBuiltin: true,
        isEnabled: true,
      },
    ];
  }
  return invoke<ClassificationRule[]>("list_rules");
}

export async function createRule(draft: RuleDraft): Promise<ClassificationRule> {
  if (!("__TAURI_INTERNALS__" in window)) {
    return {
      id: `user:${draft.ruleType}:${draft.pattern}`,
      ...draft,
      priority: 100,
      isBuiltin: false,
      isEnabled: true,
    };
  }
  return invoke<ClassificationRule>("create_rule", { draft });
}
```

- [ ] **Step 3: Build rules settings UI**

Create `src/components/rules/RulesSettings.tsx`:

```tsx
import { useEffect, useState } from "react";
import { createRule, listRules } from "../../api/activityApi";
import type { ClassificationRule, ProductivityCategory, RuleType } from "../../types/activity";

export function RulesSettings() {
  const [rules, setRules] = useState<ClassificationRule[]>([]);
  const [pattern, setPattern] = useState("");
  const [category, setCategory] = useState<ProductivityCategory>("productive");
  const [ruleType, setRuleType] = useState<RuleType>("domain");

  useEffect(() => {
    void listRules().then(setRules);
  }, []);

  async function submitRule(event: React.FormEvent) {
    event.preventDefault();
    const rule = await createRule({ name: pattern, pattern, category, ruleType });
    setRules((current) => [rule, ...current]);
    setPattern("");
  }

  return (
    <section className="dashboard-section" aria-labelledby="rules-heading">
      <div className="section-heading">
        <h2 id="rules-heading">Rules</h2>
        <span>{rules.length} rules</span>
      </div>
      <form className="rule-form" onSubmit={submitRule}>
        <select value={ruleType} onChange={(event) => setRuleType(event.target.value as RuleType)}>
          <option value="domain">Domain</option>
          <option value="app">App</option>
          <option value="titleKeyword">Title keyword</option>
        </select>
        <input value={pattern} onChange={(event) => setPattern(event.target.value)} aria-label="Rule pattern, for example youtube.com" />
        <select value={category} onChange={(event) => setCategory(event.target.value as ProductivityCategory)}>
          <option value="productive">Productive</option>
          <option value="unproductive">Unproductive</option>
          <option value="neutral">Neutral</option>
          <option value="ignored">Ignored</option>
        </select>
        <button type="submit" disabled={!pattern.trim()}>Add</button>
      </form>
      <div className="table-panel">
        <table>
          <thead>
            <tr><th>Name</th><th>Type</th><th>Pattern</th><th>Category</th><th>Source</th></tr>
          </thead>
          <tbody>
            {rules.map((rule) => (
              <tr key={rule.id}>
                <td>{rule.name}</td>
                <td>{rule.ruleType}</td>
                <td>{rule.pattern}</td>
                <td>{rule.category}</td>
                <td>{rule.isBuiltin ? "Preset" : "Custom"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
```

- [ ] **Step 4: Add uncategorized review component**

Create `src/components/rules/UncategorizedReview.tsx`:

```tsx
import { createRule } from "../../api/activityApi";
import type { ActivitySession, ProductivityCategory } from "../../types/activity";

export function UncategorizedReview({ sessions, onRuleCreated }: { sessions: ActivitySession[]; onRuleCreated: () => void }) {
  const uncategorized = sessions.filter((session) => session.category === "uncategorized");

  async function classify(session: ActivitySession, category: ProductivityCategory) {
    await createRule({
      name: session.domain ?? session.appName,
      ruleType: session.domain ? "domain" : "app",
      pattern: session.domain ?? session.processName,
      category,
    });
    onRuleCreated();
  }

  return (
    <section className="dashboard-section" aria-labelledby="uncategorized-heading">
      <div className="section-heading">
        <h2 id="uncategorized-heading">Uncategorized</h2>
        <span>{uncategorized.length} items</span>
      </div>
      <div className="table-panel">
        <table>
          <tbody>
            {uncategorized.map((session) => (
              <tr key={session.id}>
                <td>{session.domain ?? session.appName}</td>
                <td>{session.windowTitle}</td>
                <td><button onClick={() => classify(session, "productive")}>Productive</button></td>
                <td><button onClick={() => classify(session, "unproductive")}>Unproductive</button></td>
                <td><button onClick={() => classify(session, "neutral")}>Neutral</button></td>
                <td><button onClick={() => classify(session, "ignored")}>Ignore</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
```

- [ ] **Step 5: Add Rust command tests for rule creation**

Add this repository test:

```rust
#[cfg(test)]
mod rule_tests {
    use super::*;
    use crate::domain::rules::{ClassificationRule, ProductivityCategory, RuleType};

    #[test]
    fn saves_custom_rule_before_builtin_rules() {
        let repo = Repository::in_memory_for_test().expect("repo");
        let rule = ClassificationRule {
            id: "user:domain:youtube.com".into(),
            name: "YouTube Lectures".into(),
            rule_type: RuleType::Domain,
            pattern: "youtube.com".into(),
            category: ProductivityCategory::Productive,
            priority: 100,
            is_builtin: false,
            is_enabled: true,
        };

        repo.save_rule(&rule).expect("saved");
        let rules = repo.list_rules().expect("rules");

        assert_eq!(rules[0].pattern, "youtube.com");
        assert!(!rules[0].is_builtin);
    }
}
```

- [ ] **Step 6: Implement rule repository methods and Tauri commands**

Add DTO and commands:

```rust
#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleDraftDto {
    pub name: String,
    pub rule_type: crate::domain::rules::RuleType,
    pub pattern: String,
    pub category: crate::domain::rules::ProductivityCategory,
}

#[tauri::command]
pub fn list_rules(state: State<AppState>) -> Result<Vec<crate::domain::rules::ClassificationRule>, String> {
    state.repository.lock().unwrap().list_rules().map_err(|error| error.to_string())
}

#[tauri::command]
pub fn create_rule(
    state: State<AppState>,
    draft: RuleDraftDto,
) -> Result<crate::domain::rules::ClassificationRule, String> {
    let rule = crate::domain::rules::ClassificationRule {
        id: format!("user:{:?}:{}", draft.rule_type, draft.pattern),
        name: draft.name,
        rule_type: draft.rule_type,
        pattern: draft.pattern,
        category: draft.category,
        priority: 100,
        is_builtin: false,
        is_enabled: true,
    };
    state.repository.lock().unwrap().save_rule(&rule).map_err(|error| error.to_string())?;
    Ok(rule)
}
```

- [ ] **Step 7: Register commands and compose UI**

Add `RulesSettings` and `UncategorizedReview` to `App.tsx`. Register `list_rules` and `create_rule` in `generate_handler`.

- [ ] **Step 8: Run tests**

Run:

```powershell
npm test
cd src-tauri
cargo test
cd ..
```

Expected: PASS.

- [ ] **Step 9: Commit**

```powershell
git add src src-tauri
git commit -m "feat: manage classification rules"
```

## Task 10: Add Collector Service, Pause Controls, and Tray

**Files:**
- Create: `src-tauri/src/collector/service.rs`
- Create: `src-tauri/src/tray.rs`
- Modify: `src-tauri/src/collector/mod.rs`
- Modify: `src-tauri/src/app_state.rs`
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add collector status state**

Update `src-tauri/src/app_state.rs`:

```rust
use std::sync::{Arc, Mutex};
use chrono::{DateTime, Utc};

use crate::storage::repository::Repository;

#[derive(Debug, Clone)]
pub struct TrackingStatus {
    pub paused_until: Option<DateTime<Utc>>,
}

impl TrackingStatus {
    pub fn is_paused(&self) -> bool {
        self.paused_until.map(|until| until > Utc::now()).unwrap_or(false)
    }
}

pub struct AppState {
    pub repository: Arc<Mutex<Repository>>,
    pub tracking_status: Mutex<TrackingStatus>,
}
```

- [ ] **Step 2: Write status test**

Add tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paused_until_future_counts_as_paused() {
        let status = TrackingStatus {
            paused_until: Some(Utc::now() + chrono::Duration::minutes(15)),
        };
        assert!(status.is_paused());
    }
}
```

- [ ] **Step 3: Implement pause/resume commands**

Add to `src-tauri/src/commands.rs`:

```rust
#[tauri::command]
pub fn pause_tracking(state: State<AppState>, minutes: i64) -> Result<(), String> {
    let mut status = state.tracking_status.lock().unwrap();
    status.paused_until = Some(chrono::Utc::now() + chrono::Duration::minutes(minutes));
    Ok(())
}

#[tauri::command]
pub fn resume_tracking(state: State<AppState>) -> Result<(), String> {
    let mut status = state.tracking_status.lock().unwrap();
    status.paused_until = None;
    Ok(())
}
```

- [ ] **Step 4: Add tray menu**

Create `src-tauri/src/tray.rs`:

```rust
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
    let pause_day = MenuItem::with_id(app, "pause_day", "Pause until tomorrow", true, None::<&str>)?;
    let resume = MenuItem::with_id(app, "resume", "Resume Tracking", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &pause_15, &pause_60, &pause_day, &resume, &quit])?;

    TrayIconBuilder::new()
        .menu(&menu)
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
        })
        .build(app)?;

    Ok(())
}

fn set_pause(app: &tauri::AppHandle, duration: Duration) {
    let state = app.state::<AppState>();
    let mut status = state.tracking_status.lock().unwrap();
    status.paused_until = Some(Utc::now() + duration);
}

fn clear_pause(app: &tauri::AppHandle) {
    let state = app.state::<AppState>();
    let mut status = state.tracking_status.lock().unwrap();
    status.paused_until = None;
}
```

- [ ] **Step 5: Add collector service skeleton**

Create `src-tauri/src/collector/service.rs`:

```rust
use std::time::Duration;

pub struct CollectorService {
    pub sample_interval: Duration,
}

impl CollectorService {
    pub fn new(sample_interval: Duration) -> Self {
        Self { sample_interval }
    }

    pub fn start(self) {
        std::thread::spawn(move || loop {
            std::thread::sleep(self.sample_interval);
        });
    }
}
```

- [ ] **Step 6: Register tray and status**

Update `src-tauri/src/lib.rs` to initialize `TrackingStatus`, include tray setup, and register pause/resume commands.

- [ ] **Step 7: Run checks**

Run:

```powershell
cd src-tauri
cargo test
cargo check
cd ..
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add src-tauri
git commit -m "feat: add tracking controls"
```

## Task 11: Add Export Support

**Files:**
- Create: `src-tauri/src/export.rs`
- Modify: `src-tauri/src/commands.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src/api/activityApi.ts`

- [ ] **Step 1: Write CSV export test**

Create `src-tauri/src/export.rs`:

```rust
use crate::domain::activity::ActivitySession;

pub fn sessions_to_csv(_sessions: &[ActivitySession]) -> String {
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::activity::{ActivitySession, ActivitySource};
    use chrono::Utc;

    #[test]
    fn exports_session_headers_and_rows() {
        let now = Utc::now();
        let csv = sessions_to_csv(&[ActivitySession {
            id: "s1".into(),
            started_at: now,
            ended_at: now,
            duration_seconds: 60,
            source: ActivitySource::ActiveWindow,
            app_name: "Chrome".into(),
            process_name: "chrome.exe".into(),
            window_title: "ChatGPT".into(),
            domain: Some("chatgpt.com".into()),
            url: None,
            is_idle: false,
        }]);

        assert!(csv.contains("started_at,ended_at,duration_seconds,app_name,domain,window_title"));
        assert!(csv.contains("chatgpt.com"));
    }
}
```

- [ ] **Step 2: Run export test to verify failure**

Run:

```powershell
cd src-tauri
cargo test export::tests::exports_session_headers_and_rows
cd ..
```

Expected: FAIL because CSV content is empty.

- [ ] **Step 3: Implement CSV export**

Replace function:

```rust
pub fn sessions_to_csv(sessions: &[ActivitySession]) -> String {
    let mut csv = String::from("started_at,ended_at,duration_seconds,app_name,domain,window_title\n");
    for session in sessions {
        csv.push_str(&format!(
            "{},{},{},{},{},{}\n",
            session.started_at.to_rfc3339(),
            session.ended_at.to_rfc3339(),
            session.duration_seconds,
            session.app_name.replace(',', " "),
            session.domain.clone().unwrap_or_default().replace(',', " "),
            session.window_title.replace(',', " ")
        ));
    }
    csv
}
```

- [ ] **Step 4: Add export command**

Add command:

```rust
#[tauri::command]
pub fn export_today_csv(state: State<AppState>) -> Result<String, String> {
    let today = chrono::Utc::now().date_naive();
    let sessions = state
        .repository
        .lock()
        .unwrap()
        .list_sessions_for_day(today)
        .map_err(|error| error.to_string())?;
    Ok(crate::export::sessions_to_csv(&sessions))
}
```

- [ ] **Step 5: Run tests**

Run:

```powershell
cd src-tauri
cargo test export
cd ..
npm test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add src src-tauri
git commit -m "feat: export activity data"
```

## Task 12: Add Optional Browser Extension Bridge

**Files:**
- Create: `browser-extension/package.json`
- Create: `browser-extension/tsconfig.json`
- Create: `browser-extension/manifest.json`
- Create: `browser-extension/src/background.ts`
- Create: `browser-extension/src/background.test.ts`
- Create: `src-tauri/src/browser_bridge.rs`
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/app_state.rs`
- Modify: `src-tauri/src/storage/repository.rs`

- [ ] **Step 1: Create extension package**

Create `browser-extension/package.json`:

```json
{
  "name": "time-manager-browser-bridge",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "test": "vitest run"
  },
  "devDependencies": {
    "@types/chrome": "latest",
    "typescript": "latest",
    "vitest": "latest"
  }
}
```

- [ ] **Step 2: Create manifest**

Create `browser-extension/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "Time Manager Browser Bridge",
  "version": "0.1.0",
  "permissions": ["tabs", "activeTab"],
  "host_permissions": ["<all_urls>", "http://127.0.0.1:17321/*"],
  "background": {
    "service_worker": "dist/background.js",
    "type": "module"
  }
}
```

- [ ] **Step 3: Write URL sanitization test**

Create `browser-extension/src/background.test.ts`:

```ts
import { sanitizeUrl } from "./background";

describe("sanitizeUrl", () => {
  it("stores domain without path when full URL storage is off", () => {
    expect(sanitizeUrl("https://www.youtube.com/watch?v=abc", false)).toEqual({
      domain: "youtube.com",
      url: undefined,
    });
  });

  it("keeps full URL when enabled", () => {
    expect(sanitizeUrl("https://chatgpt.com/c/123", true)).toEqual({
      domain: "chatgpt.com",
      url: "https://chatgpt.com/c/123",
    });
  });
});
```

- [ ] **Step 4: Implement background URL sanitizer and capture**

Create `browser-extension/src/background.ts`:

```ts
export interface SanitizedUrl {
  domain: string;
  url?: string;
}

export function sanitizeUrl(rawUrl: string, storeFullUrl: boolean): SanitizedUrl {
  const parsed = new URL(rawUrl);
  const domain = parsed.hostname.replace(/^www\./, "");
  return {
    domain,
    url: storeFullUrl ? parsed.toString() : undefined,
  };
}

async function reportActiveTab(tab: chrome.tabs.Tab) {
  if (!tab.url || tab.url.startsWith("chrome://")) {
    return;
  }
  const payload = sanitizeUrl(tab.url, false);
  await fetch("http://127.0.0.1:17321/browser-event", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      title: tab.title ?? "",
      ...payload,
    }),
  }).catch(() => undefined);
}

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  const tab = await chrome.tabs.get(tabId);
  await reportActiveTab(tab);
});

chrome.tabs.onUpdated.addListener(async (_tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete") {
    await reportActiveTab(tab);
  }
});
```

- [ ] **Step 5: Install and test extension package**

Run:

```powershell
cd browser-extension
npm install
npm test
npm run build
cd ..
```

Expected: tests pass and `dist/background.js` is emitted.

- [ ] **Step 6: Add Rust local browser bridge**

Add a Rust dependency:

```powershell
cd src-tauri
cargo add tiny_http
cd ..
```

Create `src-tauri/src/browser_bridge.rs`:

```rust
use serde::Deserialize;
use std::io::Read;
use std::sync::{Arc, Mutex};
use std::thread;

use crate::storage::repository::Repository;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowserEventDraft {
    pub domain: String,
    pub url: Option<String>,
    pub title: String,
}

pub fn start_browser_bridge(repository: Arc<Mutex<Repository>>) -> anyhow::Result<()> {
    let server = tiny_http::Server::http("127.0.0.1:17321")?;
    thread::spawn(move || {
        for mut request in server.incoming_requests() {
            if request.method() != &tiny_http::Method::Post || request.url() != "/browser-event" {
                let _ = request.respond(tiny_http::Response::empty(404));
                continue;
            }

            let mut body = String::new();
            let response = match request.as_reader().read_to_string(&mut body) {
                Ok(_) => match serde_json::from_str::<BrowserEventDraft>(&body) {
                    Ok(draft) => {
                        let result = repository.lock().unwrap().save_browser_event(draft);
                        match result {
                            Ok(_) => tiny_http::Response::empty(204),
                            Err(_) => tiny_http::Response::empty(500),
                        }
                    }
                    Err(_) => tiny_http::Response::empty(400),
                },
                Err(_) => tiny_http::Response::empty(400),
            };
            let _ = request.respond(response);
        }
    });
    Ok(())
}
```

Update `src-tauri/src/app_state.rs` repository ownership:

```rust
use std::sync::{Arc, Mutex};
use chrono::{DateTime, Utc};

use crate::storage::repository::Repository;

pub struct AppState {
    pub repository: Arc<Mutex<Repository>>,
    pub tracking_status: Mutex<TrackingStatus>,
}
```

Update `src-tauri/src/lib.rs` app setup:

```rust
let repository = std::sync::Arc::new(std::sync::Mutex::new(
    Repository::open_default().expect("repository opens"),
));
crate::browser_bridge::start_browser_bridge(repository.clone()).expect("browser bridge starts");

tauri::Builder::default()
    .manage(AppState {
        repository,
        tracking_status: std::sync::Mutex::new(TrackingStatus { paused_until: None }),
    })
```

- [ ] **Step 7: Add repository test for browser events**

Add this repository test:

```rust
#[cfg(test)]
mod browser_event_tests {
    use super::*;
    use crate::browser_bridge::BrowserEventDraft;

    #[test]
    fn saves_domain_without_full_url_by_default() {
        let repo = Repository::in_memory_for_test().expect("repo");
        repo.save_browser_event(BrowserEventDraft {
            domain: "youtube.com".into(),
            url: None,
            title: "YouTube".into(),
        })
        .expect("saved");

        let events = repo.list_recent_browser_events(10).expect("events");

        assert_eq!(events[0].domain, "youtube.com");
        assert_eq!(events[0].url, None);
    }
}
```

- [ ] **Step 8: Run checks**

Run:

```powershell
cd browser-extension
npm test
npm run build
cd ..
cd src-tauri
cargo test
cargo check
cd ..
```

Expected: PASS.

- [ ] **Step 9: Commit**

```powershell
git add browser-extension src-tauri
git commit -m "feat: add browser URL bridge"
```

## Task 13: Add Playwright Visual and Layout Verification

**Files:**
- Create: `playwright.config.ts`
- Create: `tests/e2e/dashboard.spec.ts`

- [ ] **Step 1: Initialize Playwright config**

Run:

```powershell
npm init playwright@latest
```

Prompt answers:

```text
TypeScript or JavaScript? TypeScript
Tests folder name? tests/e2e
Add a GitHub Actions workflow? false
Install Playwright browsers? true
```

- [ ] **Step 2: Write dashboard smoke test**

Create `tests/e2e/dashboard.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("dashboard renders colorful analytics sections", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Time Manager" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();
  await expect(page.getByText("Top apps and sites")).toBeVisible();

  const cards = page.locator(".metric-card");
  await expect(cards).toHaveCount(5);
});
```

- [ ] **Step 3: Configure web server in `playwright.config.ts`**

Set:

```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  webServer: {
    command: "npm run dev -- --host 127.0.0.1",
    url: "http://127.0.0.1:5173",
    reuseExistingServer: true,
  },
  use: {
    baseURL: "http://127.0.0.1:5173",
    trace: "on-first-retry",
  },
  projects: [
    { name: "desktop-chrome", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile-chrome", use: { ...devices["Pixel 5"] } },
  ],
});
```

- [ ] **Step 4: Run e2e test**

Run:

```powershell
npm run e2e
```

Expected: PASS for desktop and mobile projects.

- [ ] **Step 5: Commit**

```powershell
git add playwright.config.ts tests package.json package-lock.json
git commit -m "test: verify dashboard layout"
```

## Task 14: Final Build and Windows Run Verification

**Files:**
- Modify only files required by failures found in this task.

- [ ] **Step 1: Run full frontend test suite**

Run:

```powershell
npm test
```

Expected: PASS.

- [ ] **Step 2: Run frontend production build**

Run:

```powershell
npm run build
```

Expected: PASS and `dist/` is created.

- [ ] **Step 3: Run Rust tests**

Run:

```powershell
cd src-tauri
cargo test
cd ..
```

Expected: PASS.

- [ ] **Step 4: Run Rust check**

Run:

```powershell
cd src-tauri
cargo check
cd ..
```

Expected: PASS.

- [ ] **Step 5: Run Playwright**

Run:

```powershell
npm run e2e
```

Expected: PASS.

- [ ] **Step 6: Launch Tauri dev app**

Run:

```powershell
npm run tauri dev
```

Expected: the Windows desktop app opens and shows the Time Manager dashboard. The app can be closed from the window or tray.

- [ ] **Step 7: Commit final fixes**

If any verification step required code changes, commit them:

```powershell
git add .
git commit -m "fix: complete Windows MVP verification"
```

## Self-Review

Spec coverage:

- Automatic active-window and idle tracking: Tasks 5, 6, and 10.
- Optional browser URL accuracy: Task 12.
- Local SQLite storage: Task 4.
- Customizable rules and broad presets: Tasks 2, 3, and 9.
- Colorful charts, tables, timeline, and weekly trends: Task 8.
- Pause controls and tray: Task 10.
- Export: Task 11.
- Verification: Tasks 13 and 14.

Type consistency:

- Rust categories use `ProductivityCategory` and serialize as camelCase for frontend compatibility.
- Frontend DTOs use camelCase fields matching Tauri command serialization.
- Rule order is consistent across spec, Rust rule types, and frontend rule form.
- Domain-specific rules outrank app and title rules.
