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
