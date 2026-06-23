import type { ReactNode } from "react";

interface ChartPanelProps {
  ariaLabel: string;
  children: ReactNode;
  className?: string;
  empty?: boolean;
  emptyText?: string;
  minHeightClassName?: string;
}

export function ChartPanel({
  ariaLabel,
  children,
  className = "",
  empty = false,
  emptyText,
  minHeightClassName = "min-h-[250px]",
}: ChartPanelProps) {
  return (
    <div
      className={`${minHeightClassName} rounded-lg border bg-gradient-to-b from-card to-muted/30 p-3 ${className}`}
      role="img"
      aria-label={ariaLabel}
    >
      {empty ? (
        <p className="grid min-h-[210px] place-items-center text-center text-sm font-semibold text-muted-foreground">
          {emptyText}
        </p>
      ) : (
        children
      )}
    </div>
  );
}
