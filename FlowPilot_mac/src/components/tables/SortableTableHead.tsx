import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { Button } from "../ui/button";
import { TableHead } from "../ui/table";

type SortState = false | "asc" | "desc";

interface SortableTableHeadProps {
  canSort: boolean;
  className?: string;
  label: string;
  sortState: SortState;
  toggleSorting: () => void;
}

function sortLabel(label: string, sortState: SortState): string {
  if (sortState === "asc") {
    return `${label} 오름차순 정렬됨`;
  }

  if (sortState === "desc") {
    return `${label} 내림차순 정렬됨`;
  }

  return `${label} 정렬`;
}

export function SortableTableHead({
  canSort,
  className,
  label,
  sortState,
  toggleSorting,
}: SortableTableHeadProps) {
  if (!canSort) {
    return (
      <TableHead className={className} scope="col">
        {label}
      </TableHead>
    );
  }

  const Icon = sortState === "asc" ? ArrowUp : sortState === "desc" ? ArrowDown : ChevronsUpDown;

  return (
    <TableHead className={className} scope="col">
      <Button
        aria-label={sortLabel(label, sortState)}
        className="h-8 justify-start px-0 text-xs uppercase text-muted-foreground"
        onClick={toggleSorting}
        size="sm"
        type="button"
        variant="ghost"
      >
        {label}
        <Icon aria-hidden="true" className="size-3.5" />
      </Button>
    </TableHead>
  );
}
