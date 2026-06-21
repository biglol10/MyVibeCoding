import { FormEvent, useEffect, useState } from "react";
import { Pencil, Plus, RotateCcw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createActivityGroup, deleteActivityGroup, listActivityGroups, updateActivityGroup } from "../../api/activityApi";
import { RULE_TYPE_LABELS } from "../../lib/labels";
import type { ActivityGroup, RuleType } from "../../types/activity";

interface ActivityGroupsSettingsProps {
  onChanged?: () => void;
}

const GROUP_RULE_TYPES: RuleType[] = ["domain", "app", "titleKeyword", "urlPattern"];
const SORT_OPTIONS: Intl.CollatorOptions = { numeric: true, sensitivity: "base" };
const GROUP_RULE_TYPE_LABELS: Record<RuleType, string> = {
  domain: "도메인 묶음",
  app: "앱 묶음",
  titleKeyword: "제목 키워드 묶음",
  urlPattern: "URL 패턴 묶음",
};

function compareTextAsc(left: string, right: string): number {
  return left.localeCompare(right, "ko-KR", SORT_OPTIONS);
}

function firstMatcherPattern(group: ActivityGroup): string {
  return group.matchers[0]?.pattern ?? "";
}

function compareGroupsByNameAsc(left: ActivityGroup, right: ActivityGroup): number {
  return (
    compareTextAsc(left.name, right.name) ||
    compareTextAsc(firstMatcherPattern(left), firstMatcherPattern(right)) ||
    compareTextAsc(left.id, right.id)
  );
}

export function ActivityGroupsSettings({ onChanged }: ActivityGroupsSettingsProps) {
  const [groups, setGroups] = useState<ActivityGroup[]>([]);
  const [name, setName] = useState("");
  const [color, setColor] = useState("#2563eb");
  const [ruleType, setRuleType] = useState<RuleType>("domain");
  const [pattern, setPattern] = useState("");
  const [editingGroupId, setEditingGroupId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    let isMounted = true;
    void listActivityGroups()
      .then((rows) => {
        if (isMounted) {
          setGroups(rows);
        }
      })
      .catch((caughtError) => {
        if (isMounted) {
          setError(caughtError instanceof Error ? caughtError.message : "그룹을 불러오지 못했습니다.");
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

  function resetForm() {
    setName("");
    setColor("#2563eb");
    setRuleType("domain");
    setPattern("");
    setEditingGroupId(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    try {
      setIsSaving(true);
      setError(null);
      const draft = {
        color,
        matchers: [{ pattern: pattern.trim(), ruleType }],
        name: name.trim(),
      };
      const group = editingGroupId
        ? await updateActivityGroup(editingGroupId, draft)
        : await createActivityGroup(draft);
      setGroups((current) => [group, ...current.filter((entry) => entry.id !== group.id)]);
      resetForm();
      onChanged?.();
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "그룹을 저장하지 못했습니다.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleDelete(groupId: string) {
    await deleteActivityGroup(groupId);
    setGroups((current) => current.filter((group) => group.id !== groupId));
    if (editingGroupId === groupId) {
      resetForm();
    }
    onChanged?.();
  }

  function handleEdit(group: ActivityGroup) {
    const matcher = group.matchers[0];
    setEditingGroupId(group.id);
    setName(group.name);
    setColor(group.color);
    setRuleType(matcher?.ruleType ?? "domain");
    setPattern(matcher?.pattern ?? "");
    setError(null);
  }

  const sortedGroups = [...groups].sort(compareGroupsByNameAsc);

  return (
    <Card aria-labelledby="activity-groups-title">
      <CardHeader className="border-b">
        <CardTitle id="activity-groups-title">앱/사이트 묶음</CardTitle>
        <CardDescription>{groups.length > 0 ? `${groups.length}개 묶음` : "리포트 표시 이름을 그룹 단위로 정리합니다."}</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4 p-5">
        <form className="grid grid-cols-[minmax(180px,1fr)_88px_170px_minmax(200px,1fr)_auto] items-end gap-3 max-xl:grid-cols-2 max-sm:grid-cols-1" onSubmit={handleSubmit}>
          <div className="grid gap-2">
            <Label htmlFor="group-name">그룹 이름</Label>
            <Input id="group-name" value={name} onChange={(event) => setName(event.target.value)} placeholder="YouTube" />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="group-color">색상</Label>
            <Input id="group-color" className="h-10 p-1" type="color" value={color} onChange={(event) => setColor(event.target.value)} />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="group-rule-type">종류</Label>
            <NativeSelect id="group-rule-type" value={ruleType} onChange={(event) => setRuleType(event.target.value as RuleType)}>
              {GROUP_RULE_TYPES.map((type) => (
                <option key={type} value={type}>
                  {GROUP_RULE_TYPE_LABELS[type]}
                </option>
              ))}
            </NativeSelect>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="group-pattern">묶음 패턴</Label>
            <Input id="group-pattern" value={pattern} onChange={(event) => setPattern(event.target.value)} placeholder="youtube.com" />
          </div>
          <div className="flex gap-2">
            <Button type="submit" disabled={isSaving || !name.trim() || !pattern.trim()}>
              <Plus className="size-4" />
              {isSaving ? "저장 중" : editingGroupId ? "묶음 저장" : "그룹 추가"}
            </Button>
            {editingGroupId ? (
              <Button variant="outline" type="button" onClick={resetForm}>
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

        {groups.length > 0 ? (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>이름</TableHead>
                <TableHead>패턴</TableHead>
                <TableHead className="text-right">관리</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sortedGroups.map((group) => (
                <TableRow key={group.id}>
                  <TableCell className="font-semibold">
                    <span className="inline-flex items-center gap-2">
                      <i className="size-2.5 rounded-full" style={{ backgroundColor: group.color }} />
                      {group.name}
                    </span>
                  </TableCell>
                  <TableCell className="max-w-96 truncate font-mono text-xs">
                    {group.matchers.map((matcher) => `${RULE_TYPE_LABELS[matcher.ruleType]}: ${matcher.pattern}`).join(", ")}
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="inline-flex gap-2">
                      <Button size="sm" variant="outline" type="button" onClick={() => handleEdit(group)}>
                        <Pencil className="size-4" />
                        수정
                      </Button>
                      <Button size="sm" variant="outline" type="button" onClick={() => void handleDelete(group.id)}>
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
            아직 등록된 묶음이 없습니다.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
