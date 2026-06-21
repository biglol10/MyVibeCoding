import { formatDuration } from "./time";

describe("formatDuration", () => {
  it("formats hours and minutes", () => {
    expect(formatDuration(3660)).toBe("1h 1m");
  });

  it("formats minutes only", () => {
    expect(formatDuration(1800)).toBe("30m");
  });
});
