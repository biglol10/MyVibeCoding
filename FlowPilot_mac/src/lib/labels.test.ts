import {
  CATEGORY_LABELS,
  EMPTY_STATE_TEXT,
  NAV_LABELS,
  RULE_SOURCE_LABELS,
  RULE_TYPE_LABELS,
  STATUS_LABELS,
} from "./labels";

describe("Korean labels", () => {
  it("covers all productivity categories with Korean text", () => {
    expect(CATEGORY_LABELS).toEqual({
      productive: "생산적",
      unproductive: "비생산",
      neutral: "중립",
      ignored: "측정 제외",
      uncategorized: "검토 필요",
    });
  });

  it("covers navigation, status, rules, and empty states", () => {
    expect(NAV_LABELS.today).toBe("오늘 요약");
    expect(NAV_LABELS.timeline).toBe("타임라인");
    expect(NAV_LABELS.weekly).toBe("주간 리포트");
    expect(NAV_LABELS.review).toBe("검토함");
    expect(NAV_LABELS.rules).toBe("분류 규칙");
    expect(STATUS_LABELS.readyDesktop).toBe("기록 중");
    expect(RULE_TYPE_LABELS.domain).toBe("도메인");
    expect(RULE_SOURCE_LABELS.builtin).toBe("기본 규칙");
    expect(EMPTY_STATE_TEXT.noUncategorized).toBe("검토할 항목이 없습니다.");
  });
});
