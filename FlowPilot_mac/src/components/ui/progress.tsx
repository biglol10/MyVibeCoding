import * as React from "react";
import { cn } from "../../lib/utils";

interface ProgressProps extends React.ComponentProps<"div"> {
  indicatorClassName?: string;
  indicatorStyle?: React.CSSProperties;
  value: number;
}

function Progress({ className, indicatorClassName, indicatorStyle, value, ...props }: ProgressProps) {
  const boundedValue = Math.max(0, Math.min(100, value));

  return (
    <div
      aria-valuemax={100}
      aria-valuemin={0}
      aria-valuenow={boundedValue}
      className={cn("relative h-2 w-full overflow-hidden rounded-full bg-secondary", className)}
      data-slot="progress"
      role="progressbar"
      {...props}
    >
      <div
        className={cn("h-full w-full flex-1 bg-primary transition-all", indicatorClassName)}
        style={{ ...indicatorStyle, transform: `translateX(-${100 - boundedValue}%)` }}
      />
    </div>
  );
}

export { Progress };
