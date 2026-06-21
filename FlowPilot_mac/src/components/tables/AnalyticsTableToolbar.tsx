import { Input } from "../ui/input";

interface AnalyticsTableToolbarProps {
  onSearchChange: (value: string) => void;
  searchLabel: string;
  searchPlaceholder: string;
  searchValue: string;
  totalRows: number;
  visibleRows: number;
}

export function AnalyticsTableToolbar({
  onSearchChange,
  searchLabel,
  searchPlaceholder,
  searchValue,
  totalRows,
  visibleRows,
}: AnalyticsTableToolbarProps) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3 border-b px-5 py-3">
      <label className="grid min-w-[220px] flex-1 gap-1.5 text-xs font-semibold text-muted-foreground">
        <span>{searchLabel}</span>
        <Input
          type="search"
          value={searchValue}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder={searchPlaceholder}
        />
      </label>
      <span className="inline-flex h-9 items-center self-end rounded-md border bg-muted/35 px-2.5 text-xs font-semibold text-muted-foreground">
        {visibleRows} / {totalRows}개 표시
      </span>
    </div>
  );
}
