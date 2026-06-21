import { FormEvent, useEffect, useState } from "react";
import { Pencil, Plus, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createRule, listRules, updateRule } from "../../api/activityApi";
import { DisplayNameOverridesSettings } from "../displayNames/DisplayNameOverridesSettings";
import { ActivityGroupsSettings } from "../groups/ActivityGroupsSettings";
import { CATEGORY_LABELS, EMPTY_STATE_TEXT, RULE_SOURCE_LABELS, RULE_TYPE_LABELS } from "../../lib/labels";
import type { ClassificationRule, ProductivityCategory, RuleDraft, RuleType } from "../../types/activity";

const RULE_TYPES: RuleType[] = ["domain", "app", "titleKeyword", "urlPattern"];
const RULE_CATEGORIES: ProductivityCategory[] = ["productive", "unproductive", "neutral", "ignored"];
const PATTERN_ERROR_ID = "rule-pattern-error";
const SORT_OPTIONS: Intl.CollatorOptions = { numeric: true, sensitivity: "base" };

function compareTextAsc(left: string, right: string): number {
  return left.localeCompare(right, "ko-KR", SORT_OPTIONS);
}

function compareRulesByNameAsc(left: ClassificationRule, right: ClassificationRule): number {
  return (
    compareTextAsc(left.name, right.name) ||
    compareTextAsc(left.pattern, right.pattern) ||
    compareTextAsc(left.id, right.id)
  );
}

type RulesState =
  | { status: "loading" }
  | { rules: ClassificationRule[]; status: "ready" }
  | { message: string; status: "error" };

interface RulesSettingsProps {
  onGroupsChanged?: () => void;
  refreshVersion?: number;
}

export function RulesSettings({ onGroupsChanged, refreshVersion = 0 }: RulesSettingsProps) {
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

  const rules = rulesState.status === "ready" ? [...rulesState.rules].sort(compareRulesByNameAsc) : [];

  return (
    <div className="grid gap-4">
      <Card aria-labelledby="rules-settings-title">
        <CardHeader className="border-b">
          <CardTitle id="rules-settings-title">규칙 관리</CardTitle>
          <CardDescription>
            {rulesState.status === "ready" ? `${rules.length}개 규칙` : "도메인, 앱, 제목 키워드, URL 패턴 규칙"}
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-4 p-5">
          <form className="grid grid-cols-[160px_minmax(220px,1fr)_180px_auto] items-end gap-3 max-xl:grid-cols-2 max-sm:grid-cols-1" onSubmit={handleSubmit}>
            <div className="grid gap-2">
              <Label htmlFor="rule-type">규칙 종류</Label>
              <NativeSelect id="rule-type" value={ruleType} onChange={(event) => setRuleType(event.target.value as RuleType)}>
                {RULE_TYPES.map((type) => (
                  <option key={type} value={type}>
                    {RULE_TYPE_LABELS[type]}
                  </option>
                ))}
              </NativeSelect>
            </div>

            <div className="grid gap-2">
              <Label htmlFor="rule-pattern">패턴</Label>
              <Input
                id="rule-pattern"
                type="text"
                value={pattern}
                onChange={(event) => setPattern(event.target.value)}
                placeholder="example.com"
                required
                aria-invalid={formError ? "true" : "false"}
                aria-describedby={formError ? PATTERN_ERROR_ID : undefined}
              />
            </div>

            <div className="grid gap-2">
              <Label htmlFor="rule-category">분류</Label>
              <NativeSelect id="rule-category" value={category} onChange={(event) => setCategory(event.target.value as ProductivityCategory)}>
                {RULE_CATEGORIES.map((option) => (
                  <option key={option} value={option}>
                    {CATEGORY_LABELS[option]}
                  </option>
                ))}
              </NativeSelect>
            </div>

            <div className="flex gap-2">
              <Button type="submit" disabled={isSaving || !pattern.trim()}>
                <Plus className="size-4" />
                {isSaving ? "저장 중" : editingRule ? "규칙 저장" : "규칙 추가"}
              </Button>
              {editingRule ? (
                <Button variant="outline" type="button" disabled={isSaving} onClick={resetForm}>
                  <RotateCcw className="size-4" />
                  취소
                </Button>
              ) : null}
            </div>
          </form>

          {formError ? (
            <p className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm font-semibold text-destructive" id={PATTERN_ERROR_ID} role="alert">
              {formError}
            </p>
          ) : null}

          {rulesState.status === "loading" ? (
            <p className="rounded-lg border border-dashed bg-muted/25 p-8 text-center text-sm font-semibold text-muted-foreground">
              분류 규칙을 불러오는 중입니다.
            </p>
          ) : null}

          {rulesState.status === "error" ? (
            <p className="rounded-lg border border-destructive/30 bg-destructive/10 p-8 text-center text-sm font-semibold text-destructive" role="alert">
              {rulesState.message}
            </p>
          ) : null}

          {rulesState.status === "ready" && rules.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>이름</TableHead>
                  <TableHead>종류</TableHead>
                  <TableHead>패턴</TableHead>
                  <TableHead>분류</TableHead>
                  <TableHead>우선순위</TableHead>
                  <TableHead>출처</TableHead>
                  <TableHead className="text-right">관리</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rules.map((rule) => (
                  <TableRow key={rule.id}>
                    <TableCell className="font-semibold">{rule.name}</TableCell>
                    <TableCell>{RULE_TYPE_LABELS[rule.ruleType]}</TableCell>
                    <TableCell className="max-w-64 truncate font-mono text-xs">{rule.pattern}</TableCell>
                    <TableCell>{CATEGORY_LABELS[rule.category]}</TableCell>
                    <TableCell>{rule.priority}</TableCell>
                    <TableCell>{rule.isBuiltin ? RULE_SOURCE_LABELS.builtin : RULE_SOURCE_LABELS.custom}</TableCell>
                    <TableCell className="text-right">
                      <Button size="sm" variant="outline" type="button" onClick={() => handleEditRule(rule)}>
                        <Pencil className="size-4" />
                        수정
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : null}

          {rulesState.status === "ready" && rules.length === 0 ? (
            <p className="rounded-lg border border-dashed bg-muted/25 p-8 text-center text-sm font-semibold text-muted-foreground">
              {EMPTY_STATE_TEXT.noRules}
            </p>
          ) : null}
        </CardContent>
      </Card>

      <DisplayNameOverridesSettings onChanged={onGroupsChanged} />
      <ActivityGroupsSettings onChanged={onGroupsChanged} />
    </div>
  );
}
