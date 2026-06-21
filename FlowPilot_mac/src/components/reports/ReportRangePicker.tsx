import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { buildCustomRange, buildRangeFromPreset, RANGE_PRESETS } from "../../lib/reportRanges";
import type { ReportRange, ReportRangePreset } from "../../types/activity";

interface ReportRangePickerProps {
  disabled?: boolean;
  onChange: (range: ReportRange) => void;
  range: ReportRange;
}

function dateInputValue(value: string): string {
  const date = new Date(value);
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function ReportRangePicker({ disabled = false, onChange, range }: ReportRangePickerProps) {
  const [customStart, setCustomStart] = useState(dateInputValue(range.start));
  const [customEnd, setCustomEnd] = useState(dateInputValue(new Date(new Date(range.end).getTime() - 1).toISOString()));

  function handlePresetClick(preset: ReportRangePreset) {
    if (preset === "custom") {
      onChange(buildCustomRange(customStart, customEnd));
      return;
    }

    onChange(buildRangeFromPreset(preset));
  }

  return (
    <div className="flex flex-wrap items-center justify-end gap-2 max-md:justify-start" aria-label="리포트 기간 선택">
      <div className="flex flex-wrap gap-1 rounded-lg bg-muted p-1" role="group" aria-label="빠른 기간">
        {RANGE_PRESETS.map((preset) => (
          <Button
            aria-pressed={range.preset === preset.id}
            disabled={disabled}
            key={preset.id}
            onClick={() => handlePresetClick(preset.id)}
            size="sm"
            type="button"
            variant={range.preset === preset.id ? "default" : "ghost"}
          >
            {preset.label}
          </Button>
        ))}
      </div>

      {range.preset === "custom" ? (
        <div className="flex flex-wrap items-center gap-2">
          <label>
            <span className="sr-only">시작일</span>
            <Input
              className="w-36"
              type="date"
              value={customStart}
              onChange={(event) => setCustomStart(event.target.value)}
              disabled={disabled}
            />
          </label>
          <span className="text-sm text-muted-foreground" aria-hidden="true">
            -
          </span>
          <label>
            <span className="sr-only">종료일</span>
            <Input
              className="w-36"
              type="date"
              value={customEnd}
              onChange={(event) => setCustomEnd(event.target.value)}
              disabled={disabled}
            />
          </label>
          <Button type="button" disabled={disabled} onClick={() => onChange(buildCustomRange(customStart, customEnd))}>
            적용
          </Button>
        </div>
      ) : null}
    </div>
  );
}
