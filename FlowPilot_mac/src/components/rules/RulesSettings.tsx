import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  type SortingState,
  useReactTable,
} from "@tanstack/react-table";
import { createRule, listRules, updateRule } from "../../api/activityApi";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT, RULE_SOURCE_LABELS, RULE_TYPE_LABELS } from "../../lib/labels";
import { cn } from "../../lib/utils";
import type { ClassificationRule, ProductivityCategory, RuleDraft, RuleType } from "../../types/activity";
import { Alert, AlertDescription } from "../ui/alert";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { Input } from "../ui/input";
import { Select } from "../ui/select";
import { Table, TableBody, TableCell, TableHeader, TableRow } from "../ui/table";
import { AnalyticsTableToolbar } from "../tables/AnalyticsTableToolbar";
import { SortableTableHead } from "../tables/SortableTableHead";

const RULE_TYPES: RuleType[] = ["domain", "app", "titleKeyword", "urlPattern"];
const RULE_CATEGORIES: ProductivityCategory[] = ["productive", "unproductive", "neutral", "ignored"];
const PATTERN_ERROR_ID = "rule-pattern-error";
const columnHelper = createColumnHelper<ClassificationRule>();
const RULE_TABLE_COLUMN_CLASSES: Record<string, string> = {
  actions: "w-[8%] text-right",
  categoryLabel: "w-[12%] text-left",
  name: "w-[22%] text-left",
  pattern: "w-[24%] text-left",
  priority: "w-[10%] text-right",
  ruleTypeLabel: "w-[10%] text-left",
  sourceLabel: "w-[14%] text-left",
};

type RulesState =
  | { status: "loading" }
  | { rules: ClassificationRule[]; status: "ready" }
  | { message: string; status: "error" };

interface RulesSettingsProps {
  refreshVersion?: number;
}

function ruleSearchText(rule: ClassificationRule): string {
  return [
    rule.name,
    rule.pattern,
    RULE_TYPE_LABELS[rule.ruleType],
    CATEGORY_LABELS[rule.category],
    rule.priority,
    rule.isBuiltin ? RULE_SOURCE_LABELS.builtin : RULE_SOURCE_LABELS.custom,
  ]
    .join(" ")
    .toLowerCase();
}

function ruleTableColumnClassName(columnId: string): string {
  return RULE_TABLE_COLUMN_CLASSES[columnId] ?? "text-left";
}

export function RulesSettings({ refreshVersion = 0 }: RulesSettingsProps) {
  const [rulesState, setRulesState] = useState<RulesState>({ status: "loading" });
  const [ruleType, setRuleType] = useState<RuleType>("domain");
  const [pattern, setPattern] = useState("");
  const [category, setCategory] = useState<ProductivityCategory>("productive");
  const [editingRule, setEditingRule] = useState<ClassificationRule | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    let isMounted = true;

    async function loadRuleRows() {
      try {
        const rules = await listRules();
        if (isMounted) {
          setRulesState({ rules, status: "ready" });
        }
      } catch (error) {
        if (isMounted) {
          setRulesState({
            message: error instanceof Error ? error.message : "분류 규칙을 불러오지 못했습니다.",
            status: "error",
          });
        }
      }
    }

    void loadRuleRows();

    return () => {
      isMounted = false;
    };
  }, [refreshVersion]);

  function resetForm() {
    setRuleType("domain");
    setPattern("");
    setCategory("productive");
    setEditingRule(null);
    setFormError(null);
  }

  function handleEditRule(rule: ClassificationRule) {
    setRuleType(rule.ruleType);
    setPattern(rule.pattern);
    setCategory(rule.category === "uncategorized" ? "neutral" : rule.category);
    setEditingRule(rule);
    setFormError(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedPattern = pattern.trim();
    if (!trimmedPattern) {
      setFormError("패턴을 입력해야 합니다.");
      return;
    }

    const draft: RuleDraft = {
      name: editingRule && editingRule.pattern === trimmedPattern ? editingRule.name : trimmedPattern,
      ruleType,
      pattern: trimmedPattern,
      category,
    };

    try {
      setIsSaving(true);
      setFormError(null);
      const savedRule = editingRule ? await updateRule(editingRule.id, draft) : await createRule(draft);
      setRulesState((current) => {
        if (current.status !== "ready") {
          return current;
        }

        if (!current.rules.some((rule) => rule.id === savedRule.id)) {
          return { rules: [savedRule, ...current.rules], status: "ready" };
        }

        let didReplace = false;
        const rules = current.rules.flatMap((rule) => {
          if (rule.id !== savedRule.id) {
            return [rule];
          }
          if (didReplace) {
            return [];
          }
          didReplace = true;
          return [savedRule];
        });

        return { rules, status: "ready" };
      });
      resetForm();
    } catch (error) {
      setFormError(error instanceof Error ? error.message : "규칙을 저장하지 못했습니다.");
    } finally {
      setIsSaving(false);
    }
  }

  const rules = rulesState.status === "ready" ? rulesState.rules : [];
  const [globalFilter, setGlobalFilter] = useState("");
  const [sorting, setSorting] = useState<SortingState>([{ id: "name", desc: false }]);
  const columns = useMemo(
    () => [
      columnHelper.accessor("name", {
        header: "이름",
        cell: (info) => <span className="font-semibold text-foreground">{info.getValue()}</span>,
      }),
      columnHelper.accessor((rule) => RULE_TYPE_LABELS[rule.ruleType], {
        id: "ruleTypeLabel",
        header: "종류",
        cell: (info) => info.getValue(),
      }),
      columnHelper.accessor("pattern", {
        header: "패턴",
        cell: (info) => (
          <span className="block max-w-60 [overflow-wrap:anywhere] text-muted-foreground">{info.getValue()}</span>
        ),
      }),
      columnHelper.accessor((rule) => CATEGORY_LABELS[rule.category], {
        id: "categoryLabel",
        header: "분류",
        cell: (info) => {
          const rule = info.row.original;
          return (
            <Badge variant={rule.category === "productive" ? "default" : "secondary"}>
              {info.getValue()}
            </Badge>
          );
        },
      }),
      columnHelper.accessor("priority", {
        header: "우선순위",
        cell: (info) => info.getValue(),
        sortDescFirst: false,
        sortingFn: "basic",
      }),
      columnHelper.accessor((rule) => (rule.isBuiltin ? RULE_SOURCE_LABELS.builtin : RULE_SOURCE_LABELS.custom), {
        id: "sourceLabel",
        header: "출처",
        cell: (info) => info.getValue(),
      }),
      columnHelper.display({
        id: "actions",
        header: "관리",
        cell: (info) => (
          <Button size="sm" type="button" onClick={() => handleEditRule(info.row.original)} variant="outline">
            수정
          </Button>
        ),
        enableSorting: false,
      }),
    ],
    [],
  );
  const table = useReactTable({
    columns,
    data: rules,
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getSortedRowModel: getSortedRowModel(),
    globalFilterFn: (row, _columnId, filterValue) => {
      return ruleSearchText(row.original).includes(String(filterValue).trim().toLowerCase());
    },
    onGlobalFilterChange: setGlobalFilter,
    onSortingChange: setSorting,
    state: { globalFilter, sorting },
  });
  const visibleRows = table.getRowModel().rows;

  return (
    <Card aria-labelledby="rules-settings-title">
      <CardHeader className="border-b">
        <div>
          <CardTitle id="rules-settings-title">규칙 관리</CardTitle>
          <CardDescription>
            {rulesState.status === "ready" ? `${rules.length}개 규칙` : "도메인, 앱, 제목 키워드 규칙"}
          </CardDescription>
        </div>
      </CardHeader>

      <CardContent className="border-b pt-4">
      <form className="grid grid-cols-[repeat(4,minmax(150px,1fr))] items-end gap-3 max-[920px]:grid-cols-2 max-[560px]:grid-cols-1" onSubmit={handleSubmit}>
        <label className="grid min-w-0 gap-1.5 text-xs font-semibold text-muted-foreground">
          <span>규칙 종류</span>
          <Select value={ruleType} onChange={(event) => setRuleType(event.target.value as RuleType)}>
            {RULE_TYPES.map((type) => (
              <option key={type} value={type}>
                {RULE_TYPE_LABELS[type]}
              </option>
            ))}
          </Select>
        </label>

        <label className="grid min-w-0 gap-1.5 text-xs font-semibold text-muted-foreground">
          <span>패턴</span>
          <Input
            type="text"
            value={pattern}
            onChange={(event) => setPattern(event.target.value)}
            placeholder="example.com"
            required
            aria-invalid={formError ? "true" : "false"}
            aria-describedby={formError ? PATTERN_ERROR_ID : undefined}
          />
        </label>

        <label className="grid min-w-0 gap-1.5 text-xs font-semibold text-muted-foreground">
          <span>분류</span>
          <Select value={category} onChange={(event) => setCategory(event.target.value as ProductivityCategory)}>
            {RULE_CATEGORIES.map((option) => (
              <option key={option} value={option}>
                {CATEGORY_LABELS[option]}
              </option>
            ))}
          </Select>
        </label>

        <div className="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] gap-2">
          <Button type="submit" disabled={isSaving || !pattern.trim()}>
            {isSaving ? "저장 중" : editingRule ? "규칙 저장" : "규칙 추가"}
          </Button>
          {editingRule ? (
            <Button type="button" disabled={isSaving} onClick={resetForm} variant="outline">
              취소
            </Button>
          ) : null}
        </div>
      </form>
      </CardContent>

      {formError ? (
        <Alert className="rounded-none border-x-0 border-t-0" id={PATTERN_ERROR_ID} variant="destructive">
          <AlertDescription>{formError}</AlertDescription>
        </Alert>
      ) : null}

      {rulesState.status === "loading" ? (
        <CardContent>
          <p className="grid min-h-36 place-items-center text-center text-sm font-semibold text-muted-foreground">
            분류 규칙을 불러오는 중입니다.
          </p>
        </CardContent>
      ) : null}

      {rulesState.status === "error" ? (
        <Alert className="rounded-none border-x-0 border-t-0" variant="destructive">
          <AlertDescription>{rulesState.message}</AlertDescription>
        </Alert>
      ) : null}

      {rulesState.status === "ready" && rules.length > 0 ? (
        <CardContent className="p-0">
          <AnalyticsTableToolbar
            searchLabel="규칙 검색"
            searchPlaceholder="이름 또는 패턴 검색"
            searchValue={globalFilter}
            onSearchChange={setGlobalFilter}
            totalRows={rules.length}
            visibleRows={visibleRows.length}
          />
          <div className="overflow-x-auto">
            <Table className="min-w-[760px] table-fixed max-[700px]:min-w-0">
              <TableHeader className="max-[700px]:hidden">
                {table.getHeaderGroups().map((headerGroup) => (
                  <TableRow key={headerGroup.id}>
                    {headerGroup.headers.map((header) => (
                      <SortableTableHead
                        key={header.id}
                        canSort={header.column.getCanSort()}
                        className={ruleTableColumnClassName(header.column.id)}
                        label={String(header.column.columnDef.header)}
                        sortState={header.column.getIsSorted()}
                        toggleSorting={header.column.getToggleSortingHandler()}
                      />
                    ))}
                  </TableRow>
                ))}
              </TableHeader>
              <TableBody>
                {visibleRows.length > 0 ? (
                  visibleRows.map((row) => (
                    <TableRow className="max-[700px]:block max-[700px]:p-5" key={row.id}>
                      {row.getVisibleCells().map((cell) => (
                        <TableCell
                          className={cn(
                            ruleTableColumnClassName(cell.column.id),
                            "max-[700px]:mt-3 max-[700px]:flex max-[700px]:items-center max-[700px]:justify-between max-[700px]:gap-4 max-[700px]:p-0",
                          )}
                          key={cell.id}
                        >
                          <span
                            aria-hidden="true"
                            className="hidden shrink-0 text-xs font-semibold text-muted-foreground max-[700px]:inline"
                          >
                            {String(cell.column.columnDef.header)}
                          </span>
                          <span className="min-w-0 max-[700px]:text-left">
                            {flexRender(cell.column.columnDef.cell, cell.getContext())}
                          </span>
                        </TableCell>
                      ))}
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell
                      className="h-32 text-center text-sm font-semibold text-muted-foreground"
                      colSpan={columns.length}
                    >
                      검색 결과가 없습니다.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      ) : null}

      {rulesState.status === "ready" && rules.length === 0 ? (
        <CardContent>
          <p className="grid min-h-36 place-items-center text-center text-sm font-semibold text-muted-foreground">
            {EMPTY_STATE_TEXT.noRules}
          </p>
        </CardContent>
      ) : null}
    </Card>
  );
}
