import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SortableTableHead } from "./SortableTableHead";

describe("SortableTableHead", () => {
  it("announces descending sort state and calls toggle handler", async () => {
    const user = userEvent.setup();
    const toggleSorting = vi.fn();

    render(
      <table>
        <thead>
          <tr>
            <SortableTableHead
              canSort
              label="시간"
              sortState="desc"
              toggleSorting={toggleSorting}
            />
          </tr>
        </thead>
      </table>,
    );

    const button = screen.getByRole("button", { name: "시간 내림차순 정렬됨" });
    await user.click(button);
    expect(toggleSorting).toHaveBeenCalledTimes(1);
  });

  it("keeps the sort button aligned to the table cell content edge", () => {
    render(
      <table>
        <thead>
          <tr>
            <SortableTableHead
              canSort
              label="이름"
              sortState="asc"
              toggleSorting={vi.fn()}
            />
          </tr>
        </thead>
      </table>,
    );

    const button = screen.getByRole("button", { name: "이름 오름차순 정렬됨" });
    expect(button).not.toHaveClass("-ml-3");
    expect(button).toHaveClass("justify-start", "px-0");
  });
});
