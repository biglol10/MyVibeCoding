import { UncategorizedReview } from "../components/rules/UncategorizedReview";
import type { ActivitySession } from "../types/activity";

interface ReviewPageProps {
  onRuleCreated: () => void;
  sessions: ActivitySession[];
}

export function ReviewPage({ onRuleCreated, sessions }: ReviewPageProps) {
  return <UncategorizedReview onRuleCreated={onRuleCreated} sessions={sessions} />;
}
