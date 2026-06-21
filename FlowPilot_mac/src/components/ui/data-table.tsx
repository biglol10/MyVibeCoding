import { useState, type ReactNode } from "react";
import {
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  type Column,
  type ColumnDef,
  type Row,
  type SortingState,
} from "@tanstack/react-table";
import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";

interface DataTableProps<TData> {
  columns: ColumnDef<TData>[];
  data: TData[];
  emptyState: ReactNode;
  getRowClassName?: (row: Row<TData>) => string | undefined;
  initialSorting?: SortingState;
}

interface SortableHeaderProps<TData> {
  align?: "left" | "right";
  children: ReactNode;
  column: Column<TData>;
}

export function SortableHeader<TData>({ align = "left", children, column }: SortableHeaderProps<TData>) {
  const sorted = column.getIsSorted();
  const Icon = sorted === "asc" ? ArrowUp : sorted === "desc" ? ArrowDown : ChevronsUpDown;

  return (
    <Button
      aria-label={`${String(children)} 정렬`}
      className={cn(
        "-mx-2 h-8 gap-1.5 rounded-md px-2 text-xs font-bold text-muted-foreground hover:bg-background hover:text-foreground",
        align === "right" && "ml-auto",
      )}
      onClick={column.getToggleSortingHandler()}
      type="button"
      variant="ghost"
    >
      <span>{children}</span>
      <Icon className="size-3.5" />
    </Button>
  );
}

export function DataTable<TData>({ columns, data, emptyState, getRowClassName, initialSorting = [] }: DataTableProps<TData>) {
  const [sorting, setSorting] = useState<SortingState>(initialSorting);
  const table = useReactTable({
    columns,
    data,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    onSortingChange: setSorting,
    state: {
      sorting,
    },
  });

  return (
    <div className="overflow-hidden">
      <Table>
        <TableHeader className="sticky top-0 z-10 bg-card/95 backdrop-blur">
          {table.getHeaderGroups().map((headerGroup) => (
            <TableRow className="hover:bg-transparent" key={headerGroup.id}>
              {headerGroup.headers.map((header) => (
                <TableHead key={header.id} style={{ width: header.getSize() }}>
                  {header.isPlaceholder ? null : flexRender(header.column.columnDef.header, header.getContext())}
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.length > 0 ? (
            table.getRowModel().rows.map((row) => (
              <TableRow className={getRowClassName?.(row)} data-state={row.getIsSelected() && "selected"} key={row.id}>
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</TableCell>
                ))}
              </TableRow>
            ))
          ) : (
            <TableRow>
              <TableCell className="py-8 text-center" colSpan={columns.length}>
                {emptyState}
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </div>
  );
}
