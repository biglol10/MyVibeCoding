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
