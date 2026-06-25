import { formatDuration } from "./time";

describe("formatDuration", () => {
  it("formats hours and minutes", () => {
    expect(formatDuration(3660)).toBe("1h 1m");
  });

  it("formats minutes only", () => {
    expect(formatDuration(1800)).toBe("30m");
  });

  it("shows sub-minute durations without collapsing them to zero minutes", () => {
    expect(formatDuration(30)).toBe("<1m");
  });
});
