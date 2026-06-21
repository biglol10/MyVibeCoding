import type { ReportRange, ReportRangePreset } from "../types/activity";

export const RANGE_PRESETS: Array<{ id: ReportRangePreset; label: string }> = [
  { id: "today", label: "오늘" },
  { id: "yesterday", label: "어제" },
  { id: "thisWeek", label: "이번 주" },
  { id: "lastWeek", label: "지난 주" },
  { id: "last30Days", label: "최근 30일" },
  { id: "custom", label: "직접 선택" },
];

const RANGE_LABELS = Object.fromEntries(RANGE_PRESETS.map((preset) => [preset.id, preset.label])) as Record<
  ReportRangePreset,
  string
>;

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

export function buildRangeFromPreset(
  preset: Exclude<ReportRangePreset, "custom">,
  now = new Date(),
): ReportRange {
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
    end: end.toISOString(),
    label: RANGE_LABELS[preset],
    preset,
    start: start.toISOString(),
  };
}

export function buildCustomRange(startDate: string, endDate: string): ReportRange {
  const start = startOfLocalDay(new Date(`${startDate}T00:00:00`));
  const end = addDays(startOfLocalDay(new Date(`${endDate}T00:00:00`)), 1);

  return {
    end: end.toISOString(),
    label: `${startDate} - ${endDate}`,
    preset: "custom",
    start: start.toISOString(),
  };
}
