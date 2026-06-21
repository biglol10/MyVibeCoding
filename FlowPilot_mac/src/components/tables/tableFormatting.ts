import { CATEGORY_LABELS, RULE_SOURCE_LABELS } from "../../lib/labels";
import type { ProductivityCategory } from "../../types/activity";

export function displayRuleSource(matchedRuleId: string | null): string {
  if (!matchedRuleId) {
    return RULE_SOURCE_LABELS.none;
  }

  if (matchedRuleId.startsWith("builtin:")) {
    return RULE_SOURCE_LABELS.builtin;
  }

  if (matchedRuleId.startsWith("user:")) {
    return RULE_SOURCE_LABELS.custom;
  }

  return matchedRuleId;
}

export function displayCategory(category: ProductivityCategory, isIdle = false): string {
  return isIdle ? "유휴" : CATEGORY_LABELS[category];
}
