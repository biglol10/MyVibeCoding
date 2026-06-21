export type ProductivityCategory =
  | "productive"
  | "unproductive"
  | "neutral"
  | "ignored"
  | "uncategorized";

export type RuleType = "domain" | "app" | "titleKeyword" | "urlPattern";

export type MacosPermissionPane = "accessibility" | "screenRecording";

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

export interface TodaySummary {
  trackedSeconds: number;
  productiveSeconds: number;
  unproductiveSeconds: number;
  neutralSeconds: number;
  idleSeconds: number;
  uncategorizedSeconds: number;
}

export interface PlatformPermissionStatus {
  platform: "macos" | "windows" | "other";
  accessibilityGranted: boolean;
  screenRecordingGranted: boolean;
  accessibilityRequiredReason: string;
  screenRecordingRequiredReason: string;
  canPromptAccessibility: boolean;
  canPromptScreenRecording: boolean;
}
