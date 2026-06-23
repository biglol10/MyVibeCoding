import { useState } from "react";
import { createRule } from "../../api/activityApi";
import { CATEGORY_ACTION_LABELS, EMPTY_STATE_TEXT, RULE_TYPE_LABELS } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ActivitySession, ProductivityCategory, RuleType } from "../../types/activity";
import { Alert, AlertDescription } from "../ui/alert";
import { Button } from "../ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";

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

  return Array.from(targets.values());
}

export function UncategorizedReview({ onRuleCreated, sessions }: UncategorizedReviewProps) {
  const [reviewedTargetKeys, setReviewedTargetKeys] = useState<Set<string>>(() => new Set());
  const reviewTargets = aggregateReviewTargets(sessions).filter(
    (target) => !reviewedTargetKeys.has(target.key),
  );
  const targetCountLabel = `${reviewTargets.length}개 항목 검토 필요`;
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
        <div>
          <CardTitle id="uncategorized-review-title">검토 대기 항목</CardTitle>
          <CardDescription>{targetCountLabel}</CardDescription>
        </div>
      </CardHeader>

      {error ? (
        <Alert className="rounded-none border-x-0 border-t-0" variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      ) : null}

      {reviewTargets.length > 0 ? (
        <CardContent className="p-0">
          <div className="overflow-x-auto">
          <Table className="min-w-full max-[640px]:block">
            <TableHeader className="max-[640px]:hidden">
              <TableRow>
                <TableHead scope="col">이름</TableHead>
                <TableHead scope="col">종류</TableHead>
                <TableHead scope="col">시간</TableHead>
                <TableHead scope="col">작업</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className="max-[640px]:block">
              {reviewTargets.map((target) => (
                <TableRow className="max-[640px]:block max-[640px]:p-5" key={target.key}>
                  <TableHead className="normal-case text-foreground max-[640px]:block max-[640px]:h-auto max-[640px]:p-0" scope="row">
                    <span className="block">{target.name}</span>
                    <span className="mt-1 block text-xs font-semibold text-muted-foreground">
                      {target.count}개 세션
                    </span>
                  </TableHead>
                  <TableCell className="max-[640px]:mt-3 max-[640px]:flex max-[640px]:justify-between max-[640px]:p-0">
                    <span className="hidden text-xs font-semibold text-muted-foreground max-[640px]:inline">종류</span>
                    {RULE_TYPE_LABELS[target.ruleType]}
                  </TableCell>
                  <TableCell className="font-medium max-[640px]:mt-2 max-[640px]:flex max-[640px]:justify-between max-[640px]:p-0">
                    <span className="hidden text-xs font-semibold text-muted-foreground max-[640px]:inline">시간</span>
                    {formatDuration(target.durationSeconds)}
                  </TableCell>
                  <TableCell className="max-[640px]:mt-4 max-[640px]:block max-[640px]:p-0">
                    <div
                      aria-label={`${target.name} 빠른 분류`}
                      className="flex flex-wrap gap-2 max-[640px]:grid max-[640px]:grid-cols-2"
                      role="group"
                    >
                      {QUICK_CATEGORIES.map((category) => (
                        <Button
                          className="max-[640px]:w-full"
                          key={category}
                          type="button"
                          disabled={creatingRule !== null}
                          onClick={() => void handleCreateRule(target, category)}
                          size="sm"
                          variant="outline"
                        >
                          {creatingRule === `${target.key}:${category}` ? "저장 중" : CATEGORY_ACTION_LABELS[category]}
                        </Button>
                      ))}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          </div>
        </CardContent>
      ) : (
        <CardContent>
          <p className="grid min-h-36 place-items-center text-center text-sm font-semibold text-muted-foreground">
            {EMPTY_STATE_TEXT.noUncategorized}
          </p>
        </CardContent>
      )}
    </Card>
  );
}
