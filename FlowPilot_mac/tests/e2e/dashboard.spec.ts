import { expect, test } from "playwright/test";

test("dashboard renders colorful analytics sections", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "FlowPilot" })).toBeVisible();
  await expect(page.getByRole("button", { name: "오늘 요약" })).toHaveAttribute("aria-current", "page");
  await expect(page.getByRole("heading", { name: "오늘 요약" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "상위 사용 항목" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "분류 규칙" })).toHaveCount(0);

  const cards = page.locator(".metric-card");
  await expect(cards).toHaveCount(4);
  await expect(cards.locator("span").filter({ hasText: /^총 기록 시간$/ })).toBeVisible();
  await expect(cards.locator("span").filter({ hasText: /^생산적 사용$/ })).toBeVisible();
  await expect(cards.locator("span").filter({ hasText: /^비생산 사용$/ })).toBeVisible();

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
