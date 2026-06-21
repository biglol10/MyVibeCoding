import type { ActivitySession } from "../types/activity";

export function isMeasuredSession(session: ActivitySession): boolean {
  return session.category !== "ignored";
}
