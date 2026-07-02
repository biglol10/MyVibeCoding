import { expect, test } from "playwright/test";

const NAV_ITEMS = ["오늘 요약", "타임라인", "주간 리포트", "미분류 검토", "분류 규칙"] as const;

test("dashboard renders colorful analytics sections", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "FlowPilot" })).toBeVisible();
  await expect(page.getByRole("button", { name: "오늘 요약" })).toHaveAttribute("aria-current", "page");
  await expect(page.getByRole("heading", { name: "오늘 요약" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "상위 사용 항목" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "분류 규칙" })).toHaveCount(0);

  const summarySection = page.getByLabel("핵심 지표");
  const cards = summarySection.locator("article");
  await expect(cards).toHaveCount(4);
  await expect(cards.filter({ hasText: "총 기록 시간" })).toBeVisible();
  await expect(cards.filter({ hasText: "생산적 사용" })).toBeVisible();
  await expect(cards.filter({ hasText: "비생산 사용" })).toBeVisible();

  const borderColors = await cards.evaluateAll((elements) =>
    elements.map((element) => getComputedStyle(element).borderLeftColor),
  );
  const visibleBorderColors = borderColors.filter(
    (color) => color && color !== "rgba(0, 0, 0, 0)" && color !== "rgb(226, 232, 240)",
  );

  expect(visibleBorderColors).toHaveLength(4);
  expect(new Set(visibleBorderColors).size).toBeGreaterThanOrEqual(3);

  await page.getByRole("button", { name: "분류 규칙" }).click();
  await expect(page.getByRole("heading", { name: "분류 규칙" })).toBeVisible();
  await expect(page.getByLabel("규칙 종류")).toBeVisible();
});

test("primary pages render without horizontal overflow", async ({ page }) => {
  await page.goto("/");

  for (const label of NAV_ITEMS) {
    await page.getByRole("button", { name: new RegExp(label) }).click();
    await expect(page.getByRole("heading", { exact: true, name: label })).toBeVisible();

    const overflow = await page.evaluate(() => {
      const width = window.innerWidth;
      const scrollWidth = Math.max(document.body.scrollWidth, document.documentElement.scrollWidth);
      return scrollWidth - width;
    });

    expect(overflow).toBeLessThanOrEqual(2);
  }
});

test("rules rows stay readable on narrow screens", async ({ page }) => {
  await page.goto("/");
  const viewportWidth = page.viewportSize()?.width ?? 0;
  test.skip(viewportWidth > 700, "narrow-screen layout only");

  await page.getByRole("button", { name: "분류 규칙" }).click();
  await expect(page.getByRole("heading", { name: "분류 규칙" })).toBeVisible();

  const firstDataRow = page.getByRole("row").filter({ hasText: "ChatGPT" }).first();
  await expect(firstDataRow).toBeVisible();

  const firstCellWidth = await firstDataRow.getByRole("cell").first().evaluate((element) => {
    return element.getBoundingClientRect().width;
  });

  expect(firstCellWidth).toBeGreaterThan(260);
});
