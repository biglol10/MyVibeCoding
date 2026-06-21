import { formatDuration } from "../../lib/time";

interface ChartTooltipPayload {
  color?: string;
  name?: string;
  value?: number | string;
}

interface ChartTooltipProps {
  active?: boolean;
  label?: string;
  nameFormatter?: (name: string) => string;
  payload?: ChartTooltipPayload[];
  valueFormatter?: (value: number | string, name: string) => string;
}

function defaultValueFormatter(value: number | string): string {
  const numericValue = Number(value);

  if (Number.isFinite(numericValue)) {
    return formatDuration(numericValue);
  }

  return String(value);
}

export function ChartTooltip({
  active,
  label,
  nameFormatter = (name) => name,
  payload,
  valueFormatter = defaultValueFormatter,
}: ChartTooltipProps) {
  if (!active || !payload || payload.length === 0) {
    return null;
  }

  return (
    <div className="rounded-md border bg-popover px-3 py-2 text-xs text-popover-foreground shadow-md">
      {label ? <p className="mb-2 font-semibold text-foreground">{label}</p> : null}
      <div className="grid gap-1.5">
        {payload.map((entry, index) => {
          const name = String(entry.name ?? "");
          const value = entry.value ?? "";

          return (
            <div className="grid grid-cols-[auto_1fr_auto] items-center gap-2" key={`${name}-${index}`}>
              <i className="size-2.5 rounded-sm" style={{ backgroundColor: entry.color ?? "currentColor" }} />
              <span className="text-muted-foreground">{nameFormatter(name)}</span>
              <strong className="font-semibold text-foreground">{valueFormatter(value, name)}</strong>
            </div>
          );
        })}
      </div>
    </div>
  );
}
