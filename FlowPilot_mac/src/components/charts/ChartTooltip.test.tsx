import { render, screen } from "@testing-library/react";
import { ChartTooltip } from "./ChartTooltip";

describe("ChartTooltip", () => {
  it("renders Korean chart tooltip rows with formatted values", () => {
    render(
      <ChartTooltip
        active
        label="월"
        payload={[
          {
            color: "#16a34a",
            name: "생산적",
            value: 1800,
          },
        ]}
        valueFormatter={(value) => `${Number(value) / 60}m`}
      />,
    );

    expect(screen.getByText("월")).toBeInTheDocument();
    expect(screen.getByText("생산적")).toBeInTheDocument();
    expect(screen.getByText("30m")).toBeInTheDocument();
  });

  it("renders nothing when inactive", () => {
    const { container } = render(<ChartTooltip active={false} payload={[]} />);

    expect(container).toBeEmptyDOMElement();
  });
});
