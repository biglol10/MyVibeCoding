import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "./AppShell";

describe("AppShell", () => {
  it("renders Korean sidebar navigation and reports selection changes", async () => {
    const user = userEvent.setup();
    const onPageChange = vi.fn();

    render(
      <AppShell currentPage="today" onPageChange={onPageChange} reviewCount={3} status="ready" statusLabel="기록 중">
        <div>본문</div>
      </AppShell>,
    );

    expect(screen.getByRole("heading", { name: "FlowPilot" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "오늘 요약" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("button", { name: "검토함 3" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "타임라인" }));

    expect(onPageChange).toHaveBeenCalledWith("timeline");
  });
});
