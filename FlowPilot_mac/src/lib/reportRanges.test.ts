import { describe, expect, it } from "vitest";
import { buildRangeFromPreset, RANGE_PRESETS } from "./reportRanges";

describe("reportRanges", () => {
  it("builds today and yesterday as local day ranges", () => {
    const now = new Date("2026-06-19T10:30:00+09:00");

    expect(buildRangeFromPreset("today", now)).toMatchObject({
      label: "오늘",
      start: "2026-06-18T15:00:00.000Z",
      end: "2026-06-19T15:00:00.000Z",
    });
    expect(buildRangeFromPreset("yesterday", now)).toMatchObject({
      label: "어제",
      start: "2026-06-17T15:00:00.000Z",
      end: "2026-06-18T15:00:00.000Z",
    });
  });

  it("ships a compact preset set for the report toolbar", () => {
    expect(RANGE_PRESETS.map((preset) => preset.id)).toEqual([
      "today",
      "yesterday",
      "thisWeek",
      "lastWeek",
      "last30Days",
      "custom",
    ]);
  });
});
