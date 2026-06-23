import { render, screen } from "@testing-library/react";
import { Button } from "./button";

describe("Button", () => {
  it("renders shadcn variant classes and preserves native button props", () => {
    render(
      <Button disabled size="sm" variant="secondary">
        저장
      </Button>,
    );

    const button = screen.getByRole("button", { name: "저장" });

    expect(button).toBeDisabled();
    expect(button).toHaveClass("bg-secondary");
    expect(button).toHaveClass("h-8");
  });
});
