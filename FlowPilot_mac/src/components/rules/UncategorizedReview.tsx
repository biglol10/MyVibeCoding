import { useState } from "react";
import { Wand2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createRule } from "../../api/activityApi";
import { CATEGORY_ACTION_LABELS, EMPTY_STATE_TEXT, RULE_TYPE_LABELS } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory, RuleType } from "../../types/activity";

interface UncategorizedReviewProps {
  onRuleCreated: () => void;
  sessions: ActivitySession[];
}

interface ReviewTarget {
  count: number;
  durationSeconds: number;
  key: string;
  name: string;
  pattern: string;
  ruleType: RuleType;
}

const QUICK_CATEGORIES: ProductivityCategory[] = ["productive", "unproductive", "neutral", "ignored"];

function ruleName(session: ActivitySession): string {
  return session.domain ?? session.appName;
}

function rulePattern(session: ActivitySession): string {
  return session.domain ?? session.processName;
}

function ruleType(session: ActivitySession): RuleType {
  return session.domain ? "domain" : "app";
}

function reviewTargetKey(target: Pick<ReviewTarget, "pattern" | "ruleType">): string {
  return `${target.ruleType}:${target.pattern}`;
}

function aggregateReviewTargets(sessions: ActivitySession[]): ReviewTarget[] {
  const targets = new Map<string, ReviewTarget>();

  for (const session of sessions) {
    if (session.category !== "uncategorized") {
      continue;
    }

    const target = {
      name: ruleName(session),
      pattern: rulePattern(session),
      ruleType: ruleType(session),
    };
    const key = reviewTargetKey(target);
    const existing = targets.get(key);

    if (existing) {
      existing.count += 1;
      existing.durationSeconds += session.durationSeconds;
    } else {
      targets.set(key, {
        ...target,
        count: 1,
        durationSeconds: session.durationSeconds,
        key,
      });
    }
  }

  return Array.from(targets.values()).sort((a, b) => {
    return b.durationSeconds - a.durationSeconds || b.count - a.count || a.name.localeCompare(b.name, "ko-KR");
  });
}

export function UncategorizedReview({ onRuleCreated, sessions }: UncategorizedReviewProps) {
  const [reviewedTargetKeys, setReviewedTargetKeys] = useState<Set<string>>(() => new Set());
  const reviewTargets = aggregateReviewTargets(sessions).filter((target) => !reviewedTargetKeys.has(target.key));
  const targetCountLabel = `${reviewTargets.length}개 항목 검토 필요`;
  const description =
    reviewTargets.length > 0 ? `${targetCountLabel} · 사용 시간이 긴 항목부터 정렬` : targetCountLabel;
  const [creatingRule, setCreatingRule] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleCreateRule(target: ReviewTarget, category: ProductivityCategory) {
    try {
      setCreatingRule(`${target.key}:${category}`);
      setError(null);
      await createRule({
        name: target.name,
        ruleType: target.ruleType,
        pattern: target.pattern,
        category,
      });
      setReviewedTargetKeys((previousKeys) => {
        const nextKeys = new Set(previousKeys);
        nextKeys.add(target.key);
        return nextKeys;
      });
      onRuleCreated();
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "규칙을 만들지 못했습니다.");
    } finally {
      setCreatingRule(null);
    }
  }

  return (
    <Card aria-labelledby="uncategorized-review-title">
      <CardHeader className="border-b">
        <CardTitle id="uncategorized-review-title">추천 규칙</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4 p-5">
        {error ? (
          <p className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm font-semibold text-destructive" role="alert">
            {error}
          </p>
        ) : null}

        {reviewTargets.length > 0 ? (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>이름</TableHead>
                <TableHead>종류</TableHead>
                <TableHead>시간</TableHead>
                <TableHead>작업</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {reviewTargets.map((target) => (
                <TableRow key={target.key}>
                  <TableCell className="font-semibold">
                    <span className="grid gap-1">
                      <span>{target.name}</span>
                      <span className="text-xs font-medium text-muted-foreground">{target.count}개 세션</span>
                    </span>
                  </TableCell>
                  <TableCell>{RULE_TYPE_LABELS[target.ruleType]}</TableCell>
                  <TableCell>{formatDuration(target.durationSeconds)}</TableCell>
                  <TableCell>
                    <div className="flex flex-wrap gap-2">
                      {QUICK_CATEGORIES.map((category) => (
                        <Button
                          key={category}
                          size="sm"
                          variant="outline"
                          type="button"
                          disabled={creatingRule !== null}
                          onClick={() => void handleCreateRule(target, category)}
                        >
                          <Wand2 className="size-4" />
                          {creatingRule === `${target.key}:${category}` ? "저장 중" : CATEGORY_ACTION_LABELS[category]}
                        </Button>
                      ))}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        ) : (
          <p className="rounded-lg border border-dashed bg-muted/25 p-8 text-center text-sm font-semibold text-muted-foreground">
            {EMPTY_STATE_TEXT.noUncategorized}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
