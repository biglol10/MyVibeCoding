import {
  createRule,
  exportTodayCsv,
  getTodaySessions,
  getTodaySummary,
  listRules,
  resetDevActivityFallbackForTest,
  updateRule,
} from "./activityApi";

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

  it("removes ignored demo sessions from reports until the rule is reclassified", async () => {
    const ignored = await createRule({
      name: "Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "ignored",
    });

    await expect(getTodaySessions()).resolves.not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appName: "Code",
        }),
      ]),
    );
    await expect(getTodaySummary()).resolves.toMatchObject({
      productiveSeconds: 2700,
      trackedSeconds: 6660,
      uncategorizedSeconds: 0,
    });

    const restored = await updateRule(ignored.id, {
      name: "Code",
      ruleType: "app",
      pattern: "Code.exe",
      category: "productive",
    });

    await expect(getTodaySessions()).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          appName: "Code",
          category: "productive",
          matchedRuleId: restored.id,
        }),
      ]),
    );
    await expect(getTodaySummary()).resolves.toMatchObject({
      productiveSeconds: 3600,
      trackedSeconds: 7560,
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
