export type ProductivityCategory =
  | "productive"
  | "unproductive"
  | "neutral"
  | "ignored"
  | "uncategorized";

export type RuleType = "domain" | "app" | "titleKeyword" | "urlPattern";

export type ReportRangePreset = "today" | "yesterday" | "thisWeek" | "lastWeek" | "last30Days" | "custom";

export interface ReportRange {
  end: string;
  label: string;
  preset: ReportRangePreset;
  start: string;
}

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

export interface ActivitySession {
  id: string;
  startedAt: string;
  endedAt: string;
  durationSeconds: number;
  appName: string;
  processName: string;
  windowTitle: string;
  domain?: string | null;
  isIdle: boolean;
  category: ProductivityCategory;
  matchedRuleId?: string | null;
}

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

export interface ActivityGroupMatcher extends ActivityGroupMatcherDraft {
  id: string;
}

export interface ActivityGroup {
  color: string;
  id: string;
  matchers: ActivityGroupMatcher[];
  name: string;
}

export interface ActivityGroupDraft {
  color: string;
  matchers: ActivityGroupMatcherDraft[];
  name: string;
}

export interface DisplayNameOverride {
  displayName: string;
  id: string;
  pattern: string;
  ruleType: RuleType;
}

export interface DisplayNameOverrideDraft {
  displayName: string;
  pattern: string;
  ruleType: RuleType;
}

export interface SessionOverrideDraft {
  categoryOverride?: ProductivityCategory | null;
  displayNameOverride?: string | null;
  note?: string | null;
  sessionId: string;
}

export interface TodaySummary {
  trackedSeconds: number;
  productiveSeconds: number;
  unproductiveSeconds: number;
  neutralSeconds: number;
  idleSeconds: number;
  uncategorizedSeconds: number;
}
