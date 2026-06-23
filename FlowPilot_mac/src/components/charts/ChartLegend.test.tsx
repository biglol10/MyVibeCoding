import { render, screen } from "@testing-library/react";
import { ChartLegend } from "./ChartLegend";

describe("ChartLegend", () => {
  it("renders compact category legend entries", () => {
    render(
      <ChartLegend
        entries={[
          { color: "#16a34a", name: "생산적" },
          { color: "#dc2626", name: "비생산" },
        ]}
      />,
    );

    expect(screen.getByText("생산적")).toBeInTheDocument();
    expect(screen.getByText("비생산")).toBeInTheDocument();
  });
});
