import { FormEvent, useEffect, useState } from "react";
import { Pencil, Plus, RotateCcw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  createDisplayNameOverride,
  deleteDisplayNameOverride,
  listDisplayNameOverrides,
  updateDisplayNameOverride,
} from "../../api/activityApi";
import { RULE_TYPE_LABELS } from "../../lib/labels";
import type { DisplayNameOverride, RuleType } from "../../types/activity";

interface DisplayNameOverridesSettingsProps {
  onChanged?: () => void;
}

const DISPLAY_NAME_RULE_TYPES: RuleType[] = ["app", "domain", "titleKeyword", "urlPattern"];
const SORT_OPTIONS: Intl.CollatorOptions = { numeric: true, sensitivity: "base" };

function compareTextAsc(left: string, right: string): number {
  return left.localeCompare(right, "ko-KR", SORT_OPTIONS);
}

function compareOverridesByDisplayNameAsc(left: DisplayNameOverride, right: DisplayNameOverride): number {
  return (
    compareTextAsc(left.displayName, right.displayName) ||
    compareTextAsc(left.pattern, right.pattern) ||
    compareTextAsc(left.id, right.id)
  );
}

export function DisplayNameOverridesSettings({ onChanged }: DisplayNameOverridesSettingsProps) {
  const [overrides, setOverrides] = useState<DisplayNameOverride[]>([]);
  const [ruleType, setRuleType] = useState<RuleType>("app");
  const [pattern, setPattern] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [editingOverrideId, setEditingOverrideId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    let isMounted = true;
    void listDisplayNameOverrides()
      .then((rows) => {
        if (isMounted) {
          setOverrides(rows);
        }
      })
      .catch((caughtError) => {
        if (isMounted) {
          setError(caughtError instanceof Error ? caughtError.message : "표시명 별칭을 불러오지 못했습니다.");
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

  function resetForm() {
    setRuleType("app");
    setPattern("");
    setDisplayName("");
    setEditingOverrideId(null);
    setError(null);
  }

  function handleEdit(overrideRow: DisplayNameOverride) {
    setRuleType(overrideRow.ruleType);
    setPattern(overrideRow.pattern);
    setDisplayName(overrideRow.displayName);
    setEditingOverrideId(overrideRow.id);
    setError(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const draft = {
      displayName: displayName.trim(),
      pattern: pattern.trim(),
      ruleType,
    };

    try {
      setIsSaving(true);
      setError(null);
      const savedOverride = editingOverrideId
        ? await updateDisplayNameOverride(editingOverrideId, draft)
        : await createDisplayNameOverride(draft);
      setOverrides((current) => [savedOverride, ...current.filter((entry) => entry.id !== savedOverride.id)]);
      resetForm();
      onChanged?.();
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "표시명 별칭을 저장하지 못했습니다.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleDelete(overrideId: string) {
    await deleteDisplayNameOverride(overrideId);
    setOverrides((current) => current.filter((entry) => entry.id !== overrideId));
    if (editingOverrideId === overrideId) {
      resetForm();
    }
    onChanged?.();
  }

  const sortedOverrides = [...overrides].sort(compareOverridesByDisplayNameAsc);

  return (
    <Card aria-labelledby="display-name-overrides-title">
      <CardHeader className="border-b">
        <CardTitle id="display-name-overrides-title">표시명 별칭</CardTitle>
        <CardDescription>
          {overrides.length > 0 ? `${overrides.length}개 별칭` : "앱과 사이트 이름을 원하는 표시명으로 바꿉니다."}
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4 p-5">
        <form className="grid grid-cols-[160px_minmax(200px,1fr)_minmax(200px,1fr)_auto] items-end gap-3 max-xl:grid-cols-2 max-sm:grid-cols-1" onSubmit={handleSubmit}>
          <div className="grid gap-2">
            <Label htmlFor="display-rule-type">대상 종류</Label>
            <NativeSelect id="display-rule-type" value={ruleType} onChange={(event) => setRuleType(event.target.value as RuleType)}>
              {DISPLAY_NAME_RULE_TYPES.map((type) => (
                <option key={type} value={type}>
                  {RULE_TYPE_LABELS[type]}
                </option>
              ))}
            </NativeSelect>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="display-pattern">식별값</Label>
            <Input id="display-pattern" value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="explorer.exe" />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="display-name">표시 이름</Label>
            <Input id="display-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="파일 탐색기" />
          </div>
          <div className="flex gap-2">
            <Button type="submit" disabled={isSaving || !pattern.trim() || !displayName.trim()}>
              <Plus className="size-4" />
              {isSaving ? "저장 중" : editingOverrideId ? "별칭 저장" : "별칭 추가"}
            </Button>
            {editingOverrideId ? (
              <Button variant="outline" type="button" disabled={isSaving} onClick={resetForm}>
                <RotateCcw className="size-4" />
                취소
              </Button>
            ) : null}
          </div>
        </form>

        {error ? (
          <p className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm font-semibold text-destructive" role="alert">
            {error}
          </p>
        ) : null}

        {overrides.length > 0 ? (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>표시 이름</TableHead>
                <TableHead>대상</TableHead>
                <TableHead>식별값</TableHead>
                <TableHead className="text-right">관리</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sortedOverrides.map((overrideRow) => (
                <TableRow key={overrideRow.id}>
                  <TableCell className="font-semibold">{overrideRow.displayName}</TableCell>
                  <TableCell>{RULE_TYPE_LABELS[overrideRow.ruleType]}</TableCell>
                  <TableCell className="max-w-64 truncate font-mono text-xs">{overrideRow.pattern}</TableCell>
                  <TableCell className="text-right">
                    <div className="inline-flex gap-2">
                      <Button size="sm" variant="outline" type="button" onClick={() => handleEdit(overrideRow)}>
                        <Pencil className="size-4" />
                        수정
                      </Button>
                      <Button size="sm" variant="outline" type="button" onClick={() => void handleDelete(overrideRow.id)}>
                        <Trash2 className="size-4" />
                        삭제
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        ) : (
          <p className="rounded-lg border border-dashed bg-muted/25 p-8 text-center text-sm font-semibold text-muted-foreground">
            아직 등록된 표시명 별칭이 없습니다.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
