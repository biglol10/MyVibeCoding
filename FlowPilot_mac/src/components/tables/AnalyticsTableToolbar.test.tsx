import { render, screen } from "@testing-library/react";
import { useState } from "react";
import userEvent from "@testing-library/user-event";
import { AnalyticsTableToolbar } from "./AnalyticsTableToolbar";

describe("AnalyticsTableToolbar", () => {
  it("renders Korean search control and row count", async () => {
    const user = userEvent.setup();
    const onSearchChange = vi.fn();

    function Harness() {
      const [searchValue, setSearchValue] = useState("");

      return (
        <AnalyticsTableToolbar
          searchLabel="사용 항목 검색"
          searchPlaceholder="앱 또는 도메인 검색"
          searchValue={searchValue}
          onSearchChange={(value) => {
            setSearchValue(value);
            onSearchChange(value);
          }}
          visibleRows={2}
          totalRows={5}
        />
      );
    }

    render(<Harness />);

    expect(screen.getByText("2 / 5개 표시")).toBeInTheDocument();
    await user.type(screen.getByLabelText("사용 항목 검색"), "chat");
    expect(onSearchChange).toHaveBeenLastCalledWith("chat");
  });

  it("aligns the row count with the search input row", () => {
    render(
      <AnalyticsTableToolbar
        searchLabel="규칙 검색"
        searchPlaceholder="이름 또는 패턴 검색"
        searchValue=""
        onSearchChange={vi.fn()}
        visibleRows={49}
        totalRows={49}
      />,
    );

    const rowCount = screen.getByText("49 / 49개 표시");
    expect(rowCount).toHaveClass("inline-flex", "h-9", "items-center", "self-end");
    expect(rowCount.parentElement).toHaveClass("items-end");
  });
});
