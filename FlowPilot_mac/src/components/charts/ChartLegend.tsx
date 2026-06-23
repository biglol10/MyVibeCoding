interface ChartLegendEntry {
  color: string;
  name: string;
  value?: string;
}

interface ChartLegendProps {
  entries: ChartLegendEntry[];
}

export function ChartLegend({ entries }: ChartLegendProps) {
  if (entries.length === 0) {
    return null;
  }

  return (
    <div className="flex flex-wrap gap-x-3 gap-y-2 px-1 text-xs font-semibold text-muted-foreground">
      {entries.map((entry) => (
        <span className="inline-flex items-center gap-1.5" key={entry.name}>
          <i className="size-2.5 rounded-sm" style={{ backgroundColor: entry.color }} />
          {entry.name}
          {entry.value ? <span className="text-foreground">{entry.value}</span> : null}
        </span>
      ))}
    </div>
  );
}
