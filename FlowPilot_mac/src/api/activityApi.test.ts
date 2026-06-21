import {
  createActivityGroup,
  createDisplayNameOverride,
  createRule,
  deleteDisplayNameOverride,
  deleteSessionOverride,
  exportTodayCsv,
  getHeatmapForRange,
  getSessionsForRange,
  getSummaryForRange,
  getTodaySessions,
  getTodaySummary,
  listDisplayNameOverrides,
  listRules,
  resetDevActivityFallbackForTest,
  updateDisplayNameOverride,
  updateRule,
  upsertSessionOverride,
} from "./activityApi";
import { buildRangeFromPreset } from "../lib/reportRanges";

beforeEach(() => {
  resetDevActivityFallbackForTest();
});

describe("createRule dev fallback", () => {
  it("canonicalizes domain patterns before building a rule", async () => {
    await expect(
      createRule({
        name: "",
        ruleType: "domain",
        pattern: " WWW.YouTube.COM. ",
        category: "unproductive",
      }),
    ).resolves.toMatchObject({
      id: "user:domain:youtube.com",
      name: "youtube.com",
      pattern: "youtube.com",
    });
  });

  it("rejects uncategorized rule categories", async () => {
    await expect(
      createRule({
        name: "Example",
        ruleType: "domain",
        pattern: "example.com",
        category: "uncategorized",
      }),
    ).rejects.toThrow("Uncategorized cannot be used for a rule category.");
  });

  it("uses lossless non-domain pattern ID segments", async () => {
    const spaced = await createRule({
      name: "",
      ruleType: "titleKeyword",
      pattern: "deep work",
      category: "productive",
    });
    const hyphenated = await createRule({
      name: "",
      ruleType: "titleKeyword",
      pattern: "deep-work",
      category: "unproductive",
    });
    const punctuated = await createRule({
      name: "",
      ruleType: "titleKeyword",
      pattern: "deep!work",
      category: "neutral",
    });

    expect(spaced.id).toBe("user:titleKeyword:deep%20work");
    expect(hyphenated.id).toBe("user:titleKeyword:deep-work");
    expect(punctuated.id).toBe("user:titleKeyword:deep%21work");
  });
});

describe("updateRule dev fallback", () => {
  it("updates an existing rule without changing its id or source", async () => {
    const created = await createRule({
      name: "YouTube",
      ruleType: "domain",
      pattern: "youtube.com",
      category: "unproductive",
    });

    const updated = await updateRule(created.id, {
      name: "YouTube Learning",
      ruleType: "domain",
      pattern: "youtube.com",
      category: "productive",
    });

    expect(updated).toMatchObject({
      id: created.id,
      name: "YouTube Learning",
      pattern: "youtube.com",
      category: "productive",
      isBuiltin: false,
    });
    await expect(listRules()).resolves.toContainEqual(updated);
  });
});

describe("exportTodayCsv dev fallback", () => {
  it("returns csv headers outside the desktop runtime", async () => {
    await expect(exportTodayCsv()).resolves.toContain(
      "started_at,ended_at,duration_seconds,app_name,domain,window_title",
    );
  });
});

describe("interactive dev fallback", () => {
  it("returns report data for a selected range", async () => {
    const range = buildRangeFromPreset("today");

    await expect(getSummaryForRange(range)).resolves.toMatchObject({ trackedSeconds: expect.any(Number) });
    await expect(getSessionsForRange(range)).resolves.toEqual(expect.any(Array));
    await expect(getHeatmapForRange(range)).resolves.toEqual(expect.any(Array));
  });

  it("applies session overrides and groups in dev fallback", async () => {
    await upsertSessionOverride({
      sessionId: "dev-3",
      categoryOverride: "productive",
      displayNameOverride: "개발 작업",
      note: "집중 코딩",
    });
    await createActivityGroup({
      name: "AI 도구",
      color: "#2563eb",
      matchers: [{ ruleType: "domain", pattern: "chatgpt.com" }],
    });

    const sessions = await getSessionsForRange(buildRangeFromPreset("today"));

    expect(sessions).toEqual(expect.arrayContaining([expect.objectContaining({ displayName: "AI 도구" })]));
    expect(sessions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: "dev-3",
          category: "productive",
          categorySource: "override",
          displayName: "개발 작업",
          note: "집중 코딩",
        }),
      ]),
    );

    await deleteSessionOverride("dev-3");
    await expect(getSessionsForRange(buildRangeFromPreset("today"))).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ id: "dev-3", categorySource: "automatic" })]),
    );
  });

  it("classifies built-in demo destinations before custom rules", async () => {
    await expect(getTodaySessions()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          domain: "youtube.com",
          category: "unproductive",
          matchedRuleId: "builtin:domain:youtube.com",
        }),
      ]),
    );
  });

  it("persists created rules and applies them to demo sessions", async () => {
    const created = await createRule({
      name: "Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "productive",
    });

    await expect(listRules()).resolves.toContainEqual(created);
    await expect(getTodaySessions()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appName: "Code",
          category: "productive",
          matchedRuleId: created.id,
        }),
      ]),
    );
    await expect(getTodaySummary()).resolves.toMatchObject({
      productiveSeconds: 3600,
      uncategorizedSeconds: 0,
    });
  });

  it("applies global display name overrides and returns to the source name after removal", async () => {
    const created = await createDisplayNameOverride({
      displayName: "VS Code",
      pattern: "Code.exe",
      ruleType: "app",
    });

    await expect(listDisplayNameOverrides()).resolves.toContainEqual(created);
    await expect(getTodaySessions()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appName: "Code",
          displayName: "VS Code",
        }),
      ]),
    );

    const updated = await updateDisplayNameOverride(created.id, {
      displayName: "Visual Studio Code",
      pattern: "Code.exe",
      ruleType: "app",
    });
    expect(updated.displayName).toBe("Visual Studio Code");
    await expect(getTodaySessions()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appName: "Code",
          displayName: "Visual Studio Code",
        }),
      ]),
    );

    await deleteDisplayNameOverride(created.id);
    await expect(getTodaySessions()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appName: "Code",
          displayName: "Code",
        }),
      ]),
    );
  });

  it("excludes ignored demo sessions from reports", async () => {
    const ignored = await createRule({
      name: "Ignore Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "ignored",
    });

    await expect(getTodaySessions()).resolves.not.toEqual(
      expect.arrayContaining([expect.objectContaining({ matchedRuleId: ignored.id })]),
    );
    await expect(getTodaySummary()).resolves.toMatchObject({
      trackedSeconds: 6660,
      uncategorizedSeconds: 0,
    });
  });
});

describe("dev fallback default rules", () => {
  it("ships broad editable defaults for common Korean and global services", async () => {
    const names = (await listRules()).map((rule) => rule.name);

    expect(names).toEqual(
      expect.arrayContaining([
        "ChatGPT",
        "Codex",
        "YouTube",
        "Instagram",
        "Chzzk",
        "Naver",
        "Google",
        "GitHub",
      ]),
    );
  });
});
