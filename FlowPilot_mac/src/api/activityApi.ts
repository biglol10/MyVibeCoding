import { invoke } from "@tauri-apps/api/core";
import { isMeasuredSession } from "../lib/activityFilters";
import { buildRangeFromPreset } from "../lib/reportRanges";
import type {
  ActivityGroup,
  ActivityGroupDraft,
  ActivitySession,
  ClassificationRule,
  DisplayNameOverride,
  DisplayNameOverrideDraft,
  HeatmapBucket,
  ReportActivitySession,
  ReportRange,
  RuleDraft,
  SessionOverrideDraft,
  TodaySummary,
} from "../types/activity";

function todayAt(hour: number, minute: number): Date {
  const date = new Date();
  date.setHours(hour, minute, 0, 0);
  return date;
}

function devSessionTimes(hour: number, minute: number, durationSeconds: number): Pick<ActivitySession, "endedAt" | "startedAt"> {
  const startedAt = todayAt(hour, minute);
  const endedAt = new Date(startedAt.getTime() + durationSeconds * 1000);

  return {
    endedAt: endedAt.toISOString(),
    startedAt: startedAt.toISOString(),
  };
}

function buildBaseDevSessions(): ActivitySession[] {
  return [
    {
      ...devSessionTimes(9, 0, 2700),
      id: "dev-1",
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
      ...devSessionTimes(9, 46, 1800),
      id: "dev-2",
      durationSeconds: 1800,
      appName: "Chrome",
      processName: "chrome.exe",
      windowTitle: "YouTube",
      domain: "youtube.com",
      isIdle: false,
      category: "unproductive",
      matchedRuleId: "builtin:domain:youtube.com",
    },
    {
      ...devSessionTimes(10, 17, 900),
      id: "dev-3",
      durationSeconds: 900,
      appName: "Code",
      processName: "Code.exe",
      windowTitle: "Untitled workspace",
      domain: null,
      isIdle: false,
      category: "uncategorized",
      matchedRuleId: null,
    },
    {
      ...devSessionTimes(10, 33, 1080),
      id: "dev-4",
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
      ...devSessionTimes(10, 52, 1080),
      id: "dev-5",
      durationSeconds: 1080,
      appName: "Chrome",
      processName: "chrome.exe",
      windowTitle: "Chzzk",
      domain: "chzzk.naver.com",
      isIdle: false,
      category: "unproductive",
      matchedRuleId: "builtin:domain:chzzk.naver.com",
    },
  ];
}

const builtinRuleSeeds: Array<Pick<ClassificationRule, "category" | "name" | "pattern" | "ruleType">> = [
  { name: "ChatGPT", ruleType: "domain", pattern: "chatgpt.com", category: "productive" },
  { name: "OpenAI", ruleType: "domain", pattern: "openai.com", category: "productive" },
  { name: "Codex", ruleType: "app", pattern: "codex.exe", category: "productive" },
  { name: "GitHub", ruleType: "domain", pattern: "github.com", category: "productive" },
  { name: "Stack Overflow", ruleType: "domain", pattern: "stackoverflow.com", category: "productive" },
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

function buildBuiltinDevRules(): ClassificationRule[] {
  return builtinRuleSeeds.map((seed) => ({
    id: `builtin:${seed.ruleType}:${seed.pattern}`,
    priority: 0,
    isBuiltin: true,
    isEnabled: true,
    ...seed,
  }));
}

let builtinDevRules: ClassificationRule[] = buildBuiltinDevRules();
let devCustomRules: ClassificationRule[] = [];
let devGroups: ActivityGroup[] = [];
let devDisplayNameOverrides: DisplayNameOverride[] = [];
let devSessionOverrides: SessionOverrideDraft[] = [];

export function resetDevActivityFallbackForTest(): void {
  builtinDevRules = buildBuiltinDevRules();
  devCustomRules = [];
  devGroups = [];
  devDisplayNameOverrides = [];
  devSessionOverrides = [];
}

function validateRuleDraft(draft: RuleDraft): Omit<ClassificationRule, "id" | "isBuiltin" | "isEnabled" | "priority"> {
  if (draft.category === "uncategorized") {
    throw new Error("Uncategorized cannot be used for a rule category.");
  }

  const pattern = canonicalRulePattern(draft.ruleType, draft.pattern);
  if (!pattern) {
    throw new Error("Rule pattern cannot be blank.");
  }

  return {
    name: draft.name.trim() || pattern,
    ruleType: draft.ruleType,
    pattern,
    category: draft.category,
  };
}

function isDesktopRuntime(): boolean {
  return "__TAURI_INTERNALS__" in window;
}

function sanitizeCsvCell(value: string): string {
  const safeValue = /^[=+\-@]/.test(value) ? `'${value}` : value;

  if (/[",\r\n]/.test(safeValue)) {
    return `"${safeValue.replaceAll("\"", "\"\"")}"`;
  }

  return safeValue;
}

function sessionsToCsv(sessions: ActivitySession[]): string {
  let csv = "started_at,ended_at,duration_seconds,app_name,domain,window_title\n";

  for (const session of sessions) {
    csv += [
      session.startedAt,
      session.endedAt,
      session.durationSeconds,
      sanitizeCsvCell(session.appName),
      sanitizeCsvCell(session.domain ?? ""),
      sanitizeCsvCell(session.windowTitle),
    ].join(",");
    csv += "\n";
  }

  return csv;
}

function ruleSpecificity(rule: ClassificationRule): number {
  if (rule.ruleType === "urlPattern") {
    return 40;
  }

  if (rule.ruleType === "domain") {
    return 30;
  }

  if (rule.ruleType === "app") {
    return 20;
  }

  return 10;
}

function ruleOrder(rule: ClassificationRule): [number, number, number] {
  return [ruleSpecificity(rule), rule.priority, rule.pattern.length];
}

function compareRuleOrder(left: ClassificationRule, right: ClassificationRule): number {
  const leftOrder = ruleOrder(left);
  const rightOrder = ruleOrder(right);

  for (let index = 0; index < leftOrder.length; index += 1) {
    if (leftOrder[index] !== rightOrder[index]) {
      return leftOrder[index] - rightOrder[index];
    }
  }

  return 0;
}

function allDevRules(): ClassificationRule[] {
  return [...devCustomRules, ...builtinDevRules];
}

function matchesDevRule(rule: ClassificationRule, session: ActivitySession): boolean {
  if (!rule.isEnabled) {
    return false;
  }

  if (rule.ruleType === "domain") {
    const domain = session.domain ? canonicalRulePattern("domain", session.domain) : null;
    const pattern = canonicalRulePattern("domain", rule.pattern);

    return !!domain && !!pattern && (domain === pattern || domain.endsWith(`.${pattern}`));
  }

  if (rule.ruleType === "app") {
    return session.processName.toLowerCase() === rule.pattern.toLowerCase() || session.appName.toLowerCase() === rule.pattern.toLowerCase();
  }

  if (rule.ruleType === "titleKeyword") {
    return session.windowTitle.toLowerCase().includes(rule.pattern.trim().toLowerCase());
  }

  return false;
}

function matchesDraftMatcher(matcher: { pattern: string; ruleType: RuleDraft["ruleType"] }, session: ActivitySession): boolean {
  if (matcher.ruleType === "domain") {
    const domain = session.domain ? canonicalRulePattern("domain", session.domain) : null;
    const pattern = canonicalRulePattern("domain", matcher.pattern);

    return !!domain && !!pattern && (domain === pattern || domain.endsWith(`.${pattern}`));
  }

  if (matcher.ruleType === "app") {
    return (
      session.processName.toLowerCase() === matcher.pattern.toLowerCase() ||
      session.appName.toLowerCase() === matcher.pattern.toLowerCase()
    );
  }

  if (matcher.ruleType === "titleKeyword") {
    return session.windowTitle.toLowerCase().includes(matcher.pattern.trim().toLowerCase());
  }

  return false;
}

function compareDisplayNameOverrideOrder(left: DisplayNameOverride, right: DisplayNameOverride): number {
  const leftOrder: [number, number] = [ruleSpecificity({ ...left, category: "neutral", isBuiltin: false, isEnabled: true, priority: 100, name: left.displayName }), left.pattern.length];
  const rightOrder: [number, number] = [ruleSpecificity({ ...right, category: "neutral", isBuiltin: false, isEnabled: true, priority: 100, name: right.displayName }), right.pattern.length];

  for (let index = 0; index < leftOrder.length; index += 1) {
    if (leftOrder[index] !== rightOrder[index]) {
      return leftOrder[index] - rightOrder[index];
    }
  }

  return 0;
}

function classifyDevSession(session: ActivitySession): Pick<ActivitySession, "category" | "matchedRuleId"> {
  const userRule = devCustomRules.filter((rule) => matchesDevRule(rule, session)).sort(compareRuleOrder).at(-1);
  const builtinRule = builtinDevRules.filter((rule) => matchesDevRule(rule, session)).sort(compareRuleOrder).at(-1);
  const matchedRule = userRule ?? builtinRule;

  return {
    category: matchedRule?.category ?? "uncategorized",
    matchedRuleId: matchedRule?.id ?? null,
  };
}

function displayNameForDevSession(session: ActivitySession, override?: SessionOverrideDraft): string {
  if (override?.displayNameOverride?.trim()) {
    return override.displayNameOverride.trim();
  }

  const displayNameOverride = devDisplayNameOverrides
    .filter((candidate) => matchesDraftMatcher(candidate, session))
    .sort(compareDisplayNameOverrideOrder)
    .at(-1);
  if (displayNameOverride) {
    return displayNameOverride.displayName;
  }

  const group = devGroups.find((candidate) => {
    return candidate.matchers.some((matcher) => matchesDraftMatcher(matcher, session));
  });

  return group?.name ?? session.domain ?? session.appName;
}

function getDevSessions(): ReportActivitySession[] {
  return buildBaseDevSessions().map((session) => ({
    ...session,
    ...classifyDevSession(session),
  })).map((session) => {
    const override = devSessionOverrides.find((entry) => entry.sessionId === session.id);
    const category = override?.categoryOverride ?? session.category;

    return {
      ...session,
      category,
      categorySource: override?.categoryOverride ? "override" : "automatic",
      displayName: displayNameForDevSession(session, override),
      matchedRuleId: override?.categoryOverride ? null : session.matchedRuleId,
      note: override?.note?.trim() || null,
    };
  });
}

function getMeasuredDevSessions(): ReportActivitySession[] {
  return getDevSessions().filter(isMeasuredSession);
}

function getDevSessionsForRange(range: ReportRange): ReportActivitySession[] {
  const start = new Date(range.start).getTime();
  const end = new Date(range.end).getTime();

  return getMeasuredDevSessions().filter((session) => {
    const startedAt = new Date(session.startedAt).getTime();
    return startedAt >= start && startedAt < end;
  });
}

function summarizeSessions(sessions: ActivitySession[]): TodaySummary {
  return sessions.reduce<TodaySummary>(
    (summary, session) => {
      if (!isMeasuredSession(session)) {
        return summary;
      }

      summary.trackedSeconds += session.durationSeconds;

      if (session.isIdle) {
        summary.idleSeconds += session.durationSeconds;
        return summary;
      }

      if (session.category === "productive") {
        summary.productiveSeconds += session.durationSeconds;
      } else if (session.category === "unproductive") {
        summary.unproductiveSeconds += session.durationSeconds;
      } else if (session.category === "neutral") {
        summary.neutralSeconds += session.durationSeconds;
      } else if (session.category === "uncategorized") {
        summary.uncategorizedSeconds += session.durationSeconds;
      }

      return summary;
    },
    {
      trackedSeconds: 0,
      productiveSeconds: 0,
      unproductiveSeconds: 0,
      neutralSeconds: 0,
      idleSeconds: 0,
      uncategorizedSeconds: 0,
    },
  );
}

function buildHeatmapBuckets(sessions: ReportActivitySession[]): HeatmapBucket[] {
  const totals = new Map<string, { categories: Map<ReportActivitySession["category"], number>; seconds: number }>();

  for (const session of sessions) {
    const startedAt = new Date(session.startedAt);
    const weekday = (startedAt.getDay() + 6) % 7;
    const hour = startedAt.getHours();
    const key = `${weekday}:${hour}`;
    const bucket = totals.get(key) ?? { categories: new Map(), seconds: 0 };
    bucket.seconds += session.durationSeconds;
    bucket.categories.set(session.category, (bucket.categories.get(session.category) ?? 0) + session.durationSeconds);
    totals.set(key, bucket);
  }

  return [...totals.entries()]
    .map(([key, bucket]) => {
      const [weekday, hour] = key.split(":").map(Number);
      const dominantCategory =
        [...bucket.categories.entries()].sort((left, right) => right[1] - left[1])[0]?.[0] ?? "uncategorized";

      return { dominantCategory, hour, seconds: bucket.seconds, weekday };
    })
    .sort((left, right) => left.weekday - right.weekday || left.hour - right.hour);
}

function ruleTypeIdSegment(ruleType: RuleDraft["ruleType"]): string {
  return ruleType;
}

function isPatternIdUnreservedByte(byte: number): boolean {
  return (
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a) ||
    (byte >= 0x30 && byte <= 0x39) ||
    byte === 0x2e ||
    byte === 0x5f ||
    byte === 0x2d ||
    byte === 0x7e
  );
}

function patternIdSegment(pattern: string): string {
  let segment = "";

  for (const byte of new TextEncoder().encode(pattern)) {
    if (isPatternIdUnreservedByte(byte)) {
      segment += String.fromCharCode(byte);
    } else {
      segment += `%${byte.toString(16).toUpperCase().padStart(2, "0")}`;
    }
  }

  return segment;
}

function canonicalRulePattern(ruleType: RuleDraft["ruleType"], pattern: string): string | null {
  if (ruleType === "domain") {
    let normalized = pattern.trim().toLowerCase();
    if (normalized.startsWith("www.")) {
      normalized = normalized.slice(4);
    }
    normalized = normalized.replace(/\.+$/, "");

    return normalized || null;
  }

  const trimmed = pattern.trim();
  return trimmed || null;
}

export async function getSummaryForRange(range: ReportRange): Promise<TodaySummary> {
  if (!isDesktopRuntime()) {
    return summarizeSessions(getDevSessionsForRange(range));
  }
  return invoke<TodaySummary>("get_summary_for_range", { start: range.start, end: range.end });
}

export async function getSessionsForRange(range: ReportRange): Promise<ReportActivitySession[]> {
  if (!isDesktopRuntime()) {
    return getDevSessionsForRange(range);
  }
  return invoke<ReportActivitySession[]>("get_sessions_for_range", { start: range.start, end: range.end });
}

export async function getHeatmapForRange(range: ReportRange): Promise<HeatmapBucket[]> {
  if (!isDesktopRuntime()) {
    return buildHeatmapBuckets(getDevSessionsForRange(range));
  }
  return invoke<HeatmapBucket[]>("get_heatmap_for_range", { start: range.start, end: range.end });
}

export async function getTodaySummary(): Promise<TodaySummary> {
  return getSummaryForRange(buildRangeFromPreset("today"));
}

export async function getTodaySessions(): Promise<ReportActivitySession[]> {
  return getSessionsForRange(buildRangeFromPreset("today"));
}

export async function exportTodayCsv(): Promise<string> {
  if (!isDesktopRuntime()) {
    return sessionsToCsv(getDevSessions());
  }
  return invoke<string>("export_today_csv");
}

export async function listRules(): Promise<ClassificationRule[]> {
  if (!isDesktopRuntime()) {
    return allDevRules();
  }
  return invoke<ClassificationRule[]>("list_rules");
}

export async function createRule(draft: RuleDraft): Promise<ClassificationRule> {
  if (!isDesktopRuntime()) {
    const normalizedDraft = validateRuleDraft(draft);
    const createdRule = {
      ...normalizedDraft,
      id: `user:${ruleTypeIdSegment(normalizedDraft.ruleType)}:${patternIdSegment(normalizedDraft.pattern)}`,
      priority: 100,
      isBuiltin: false,
      isEnabled: true,
    };
    devCustomRules = [createdRule, ...devCustomRules.filter((rule) => rule.id !== createdRule.id)];

    return createdRule;
  }

  return invoke<ClassificationRule>("create_rule", { draft });
}

export async function updateRule(ruleId: string, draft: RuleDraft): Promise<ClassificationRule> {
  if (!isDesktopRuntime()) {
    const normalizedDraft = validateRuleDraft(draft);
    const existingRule = allDevRules().find((rule) => rule.id === ruleId);

    if (!existingRule) {
      throw new Error("Rule not found.");
    }

    const updatedRule: ClassificationRule = {
      ...existingRule,
      ...normalizedDraft,
    };

    if (updatedRule.isBuiltin) {
      builtinDevRules = builtinDevRules.map((rule) => (rule.id === updatedRule.id ? updatedRule : rule));
    } else {
      devCustomRules = devCustomRules.map((rule) => (rule.id === updatedRule.id ? updatedRule : rule));
    }

    return updatedRule;
  }

  return invoke<ClassificationRule>("update_rule", { ruleId, draft });
}

function normalizeGroupDraft(draft: ActivityGroupDraft): ActivityGroupDraft {
  const name = draft.name.trim();
  if (!name) {
    throw new Error("그룹 이름을 입력해야 합니다.");
  }

  const matchers = draft.matchers
    .map((matcher) => ({
      ruleType: matcher.ruleType,
      pattern: canonicalRulePattern(matcher.ruleType, matcher.pattern) ?? "",
    }))
    .filter((matcher) => matcher.pattern);

  if (matchers.length === 0) {
    throw new Error("그룹에는 최소 1개의 패턴이 필요합니다.");
  }

  return {
    color: draft.color.trim() || "#2563eb",
    matchers,
    name,
  };
}

export async function listActivityGroups(): Promise<ActivityGroup[]> {
  if (!isDesktopRuntime()) {
    return devGroups;
  }
  return invoke<ActivityGroup[]>("list_activity_groups");
}

export async function createActivityGroup(draft: ActivityGroupDraft): Promise<ActivityGroup> {
  if (!isDesktopRuntime()) {
    const normalized = normalizeGroupDraft(draft);
    const id = `group:${patternIdSegment(normalized.name)}:${devGroups.length + 1}`;
    const group: ActivityGroup = {
      ...normalized,
      id,
      matchers: normalized.matchers.map((matcher, index) => ({
        ...matcher,
        id: `${id}:matcher:${index}`,
      })),
    };
    devGroups = [group, ...devGroups];
    return group;
  }

  return invoke<ActivityGroup>("create_activity_group", { draft });
}

export async function updateActivityGroup(groupId: string, draft: ActivityGroupDraft): Promise<ActivityGroup> {
  if (!isDesktopRuntime()) {
    const normalized = normalizeGroupDraft(draft);
    const group: ActivityGroup = {
      ...normalized,
      id: groupId,
      matchers: normalized.matchers.map((matcher, index) => ({
        ...matcher,
        id: `${groupId}:matcher:${index}`,
      })),
    };
    devGroups = devGroups.map((entry) => (entry.id === groupId ? group : entry));
    return group;
  }

  return invoke<ActivityGroup>("update_activity_group", { groupId, draft });
}

export async function deleteActivityGroup(groupId: string): Promise<void> {
  if (!isDesktopRuntime()) {
    devGroups = devGroups.filter((group) => group.id !== groupId);
    return;
  }

  return invoke<void>("delete_activity_group", { groupId });
}

function normalizeDisplayNameOverrideDraft(draft: DisplayNameOverrideDraft): DisplayNameOverrideDraft {
  const pattern = canonicalRulePattern(draft.ruleType, draft.pattern);
  if (!pattern) {
    throw new Error("표시명을 적용할 식별값을 입력해야 합니다.");
  }

  const displayName = draft.displayName.trim();
  if (!displayName) {
    throw new Error("표시 이름을 입력해야 합니다.");
  }

  return {
    displayName,
    pattern,
    ruleType: draft.ruleType,
  };
}

function displayNameOverrideId(draft: DisplayNameOverrideDraft): string {
  return `display-name:${ruleTypeIdSegment(draft.ruleType)}:${patternIdSegment(draft.pattern)}`;
}

export async function listDisplayNameOverrides(): Promise<DisplayNameOverride[]> {
  if (!isDesktopRuntime()) {
    return devDisplayNameOverrides;
  }

  return invoke<DisplayNameOverride[]>("list_display_name_overrides");
}

export async function createDisplayNameOverride(draft: DisplayNameOverrideDraft): Promise<DisplayNameOverride> {
  if (!isDesktopRuntime()) {
    const normalized = normalizeDisplayNameOverrideDraft(draft);
    const created: DisplayNameOverride = {
      ...normalized,
      id: displayNameOverrideId(normalized),
    };
    devDisplayNameOverrides = [
      created,
      ...devDisplayNameOverrides.filter((entry) => entry.id !== created.id),
    ];
    return created;
  }

  return invoke<DisplayNameOverride>("create_display_name_override", { draft });
}

export async function updateDisplayNameOverride(
  overrideId: string,
  draft: DisplayNameOverrideDraft,
): Promise<DisplayNameOverride> {
  if (!isDesktopRuntime()) {
    const normalized = normalizeDisplayNameOverrideDraft(draft);
    if (!devDisplayNameOverrides.some((entry) => entry.id === overrideId)) {
      throw new Error("표시명 별칭을 찾을 수 없습니다.");
    }
    const updated: DisplayNameOverride = {
      ...normalized,
      id: overrideId,
    };
    devDisplayNameOverrides = devDisplayNameOverrides.map((entry) => (entry.id === overrideId ? updated : entry));
    return updated;
  }

  return invoke<DisplayNameOverride>("update_display_name_override", { overrideId, draft });
}

export async function deleteDisplayNameOverride(overrideId: string): Promise<void> {
  if (!isDesktopRuntime()) {
    devDisplayNameOverrides = devDisplayNameOverrides.filter((entry) => entry.id !== overrideId);
    return;
  }

  return invoke<void>("delete_display_name_override", { overrideId });
}

export async function upsertSessionOverride(draft: SessionOverrideDraft): Promise<void> {
  if (!isDesktopRuntime()) {
    devSessionOverrides = [
      {
        ...draft,
        displayNameOverride: draft.displayNameOverride?.trim() || null,
        note: draft.note?.trim() || null,
      },
      ...devSessionOverrides.filter((entry) => entry.sessionId !== draft.sessionId),
    ];
    return;
  }

  return invoke<void>("upsert_session_override", { draft });
}

export async function deleteSessionOverride(sessionId: string): Promise<void> {
  if (!isDesktopRuntime()) {
    devSessionOverrides = devSessionOverrides.filter((entry) => entry.sessionId !== sessionId);
    return;
  }

  return invoke<void>("delete_session_override", { sessionId });
}
