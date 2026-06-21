import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createActivityGroup, deleteActivityGroup, listActivityGroups, updateActivityGroup } from "../../api/activityApi";
import { ActivityGroupsSettings } from "./ActivityGroupsSettings";

vi.mock("../../api/activityApi", () => ({
  createActivityGroup: vi.fn(),
  deleteActivityGroup: vi.fn(),
  listActivityGroups: vi.fn(),
  updateActivityGroup: vi.fn(),
}));

describe("ActivityGroupsSettings", () => {
  beforeEach(() => {
    vi.mocked(listActivityGroups).mockResolvedValue([]);
    vi.mocked(createActivityGroup).mockImplementation(async (draft) => ({
      ...draft,
      id: "group:youtube",
      matchers: draft.matchers.map((matcher, index) => ({ ...matcher, id: `matcher:${index}` })),
    }));
    vi.mocked(deleteActivityGroup).mockResolvedValue(undefined);
    vi.mocked(updateActivityGroup).mockImplementation(async (groupId, draft) => ({
      ...draft,
      id: groupId,
      matchers: draft.matchers.map((matcher, index) => ({ ...matcher, id: `matcher:${index}` })),
    }));
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("creates an app/site group with a matcher", async () => {
    const user = userEvent.setup();
    const onChanged = vi.fn();
    render(<ActivityGroupsSettings onChanged={onChanged} />);

    await user.type(screen.getByLabelText("그룹 이름"), "YouTube");
    await user.type(screen.getByLabelText("묶음 패턴"), "youtube.com");
    await user.click(screen.getByRole("button", { name: /그룹 추가/ }));

    expect(await screen.findByText("YouTube")).toBeInTheDocument();
    expect(createActivityGroup).toHaveBeenCalledWith({
      color: expect.any(String),
      matchers: [{ pattern: "youtube.com", ruleType: "domain" }],
      name: "YouTube",
    });
    expect(onChanged).toHaveBeenCalled();
  });

  it("sorts activity groups by name ascending", async () => {
    vi.mocked(listActivityGroups).mockResolvedValue([
      {
        color: "#dc2626",
        id: "group:zeta",
        matchers: [{ id: "matcher:zeta", pattern: "zeta.com", ruleType: "domain" }],
        name: "Zeta",
      },
      {
        color: "#2563eb",
        id: "group:alpha",
        matchers: [{ id: "matcher:alpha", pattern: "alpha.com", ruleType: "domain" }],
        name: "Alpha",
      },
    ]);

    render(<ActivityGroupsSettings onChanged={vi.fn()} />);

    expect(await screen.findByText("Alpha")).toBeInTheDocument();
    const rows = screen.getAllByRole("row");
    expect(within(rows[1]).getByText("Alpha")).toBeInTheDocument();
    expect(within(rows[2]).getByText("Zeta")).toBeInTheDocument();
  });

  it("loads an existing group into the form and saves edits", async () => {
    const user = userEvent.setup();
    vi.mocked(listActivityGroups).mockResolvedValue([
      {
        color: "#dc2626",
        id: "group:youtube",
        matchers: [{ id: "matcher:0", pattern: "youtube.com", ruleType: "domain" }],
        name: "YouTube",
      },
    ]);
    render(<ActivityGroupsSettings onChanged={vi.fn()} />);

    const row = await screen.findByRole("row", { name: /YouTube/ });
    await user.click(within(row).getByRole("button", { name: /수정/ }));
    await user.clear(screen.getByLabelText("그룹 이름"));
    await user.type(screen.getByLabelText("그룹 이름"), "YouTube Shorts");
    await user.clear(screen.getByLabelText("묶음 패턴"));
    await user.type(screen.getByLabelText("묶음 패턴"), "youtube.com/shorts");
    await user.click(screen.getByRole("button", { name: /묶음 저장/ }));

    expect(updateActivityGroup).toHaveBeenCalledWith("group:youtube", {
      color: "#dc2626",
      matchers: [{ pattern: "youtube.com/shorts", ruleType: "domain" }],
      name: "YouTube Shorts",
    });
    expect(screen.getByRole("button", { name: /그룹 추가/ })).toBeInTheDocument();
    expect(screen.getByLabelText("그룹 이름")).toHaveValue("");
  });
});
