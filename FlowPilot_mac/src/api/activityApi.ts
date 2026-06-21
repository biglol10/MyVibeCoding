import { invoke } from "@tauri-apps/api/core";
import type {
  ActivitySession,
  ClassificationRule,
  PlatformPermissionStatus,
  MacosPermissionPane,
  RuleDraft,
  TodaySummary,
} from "../types/activity";

const baseDevSessions: ActivitySession[] = [
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
  {
    id: "dev-3",
    startedAt: new Date(Date.now() + 77 * 60 * 1000).toISOString(),
    endedAt: new Date(Date.now() + 92 * 60 * 1000).toISOString(),
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
  },
];

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

export function resetDevActivityFallbackForTest(): void {
  builtinDevRules = buildBuiltinDevRules();
  devCustomRules = [];
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

function classifyDevSession(session: ActivitySession): Pick<ActivitySession, "category" | "matchedRuleId"> {
  const userRule = devCustomRules.filter((rule) => matchesDevRule(rule, session)).sort(compareRuleOrder).at(-1);
  const builtinRule = builtinDevRules.filter((rule) => matchesDevRule(rule, session)).sort(compareRuleOrder).at(-1);
  const matchedRule = userRule ?? builtinRule;

  return {
    category: matchedRule?.category ?? "uncategorized",
    matchedRuleId: matchedRule?.id ?? null,
  };
}

function getDevSessions(): ActivitySession[] {
  return baseDevSessions.map((session) => ({
    ...session,
    ...classifyDevSession(session),
  })).filter((session) => session.category !== "ignored");
}

function summarizeSessions(sessions: ActivitySession[]): TodaySummary {
  return sessions.reduce<TodaySummary>(
    (summary, session) => {
      if (session.category === "ignored") {
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

export async function getTodaySummary(): Promise<TodaySummary> {
  if (!isDesktopRuntime()) {
    return summarizeSessions(getDevSessions());
  }
  return invoke<TodaySummary>("get_today_summary");
}

export async function getTodaySessions(): Promise<ActivitySession[]> {
  if (!isDesktopRuntime()) {
    return getDevSessions();
  }
  return invoke<ActivitySession[]>("get_today_sessions");
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

export async function getPlatformPermissionStatus(): Promise<PlatformPermissionStatus> {
  if (!isDesktopRuntime()) {
    return {
      platform: "other",
      accessibilityGranted: true,
      screenRecordingGranted: true,
      accessibilityRequiredReason: "",
      screenRecordingRequiredReason: "",
      canPromptAccessibility: false,
      canPromptScreenRecording: false,
    };
  }

  return invoke<PlatformPermissionStatus>("get_platform_permission_status");
}

export async function openMacosPermissionSettings(pane: MacosPermissionPane): Promise<void> {
  if (!isDesktopRuntime()) {
    return;
  }

  await invoke("open_macos_permission_settings", { pane });
}
