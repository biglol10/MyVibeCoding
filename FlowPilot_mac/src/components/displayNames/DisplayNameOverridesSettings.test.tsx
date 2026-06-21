import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import {
  createDisplayNameOverride,
  deleteDisplayNameOverride,
  listDisplayNameOverrides,
  updateDisplayNameOverride,
} from "../../api/activityApi";
import { DisplayNameOverridesSettings } from "./DisplayNameOverridesSettings";

vi.mock("../../api/activityApi", () => ({
  createDisplayNameOverride: vi.fn(),
  deleteDisplayNameOverride: vi.fn(),
  listDisplayNameOverrides: vi.fn(),
  updateDisplayNameOverride: vi.fn(),
}));

describe("DisplayNameOverridesSettings", () => {
  beforeEach(() => {
    vi.mocked(listDisplayNameOverrides).mockResolvedValue([]);
    vi.mocked(createDisplayNameOverride).mockImplementation(async (draft) => ({
      ...draft,
      id: "display-name:app:explorer.exe",
    }));
    vi.mocked(updateDisplayNameOverride).mockImplementation(async (overrideId, draft) => ({
      ...draft,
      id: overrideId,
    }));
    vi.mocked(deleteDisplayNameOverride).mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("creates a display name override for an app identifier", async () => {
    const user = userEvent.setup();
    render(<DisplayNameOverridesSettings onChanged={vi.fn()} />);

    await user.type(screen.getByLabelText("식별값"), "explorer.exe");
    await user.type(screen.getByLabelText("표시 이름"), "파일 탐색기");
    await user.click(screen.getByRole("button", { name: /별칭 추가/ }));

    expect(await screen.findByText("파일 탐색기")).toBeInTheDocument();
    expect(createDisplayNameOverride).toHaveBeenCalledWith({
      displayName: "파일 탐색기",
      pattern: "explorer.exe",
      ruleType: "app",
    });
  });

  it("sorts display name overrides by display name ascending", async () => {
    vi.mocked(listDisplayNameOverrides).mockResolvedValue([
      {
        displayName: "Zeta",
        id: "display-name:app:zeta.exe",
        pattern: "zeta.exe",
        ruleType: "app",
      },
      {
        displayName: "Alpha",
        id: "display-name:app:alpha.exe",
        pattern: "alpha.exe",
        ruleType: "app",
      },
    ]);

    render(<DisplayNameOverridesSettings onChanged={vi.fn()} />);

    expect(await screen.findByText("Alpha")).toBeInTheDocument();
    const rows = screen.getAllByRole("row");
    expect(within(rows[1]).getByText("Alpha")).toBeInTheDocument();
    expect(within(rows[2]).getByText("Zeta")).toBeInTheDocument();
  });

  it("loads an existing override into the form and deletes it", async () => {
    const user = userEvent.setup();
    vi.mocked(listDisplayNameOverrides).mockResolvedValue([
      {
        displayName: "파일 탐색기",
        id: "display-name:app:explorer.exe",
        pattern: "explorer.exe",
        ruleType: "app",
      },
    ]);
    const onChanged = vi.fn();
    render(<DisplayNameOverridesSettings onChanged={onChanged} />);

    const row = await screen.findByRole("row", { name: /파일 탐색기/ });
    await user.click(within(row).getByRole("button", { name: /수정/ }));
    await user.clear(screen.getByLabelText("표시 이름"));
    await user.type(screen.getByLabelText("표시 이름"), "Windows 탐색기");
    await user.click(screen.getByRole("button", { name: /별칭 저장/ }));

    expect(updateDisplayNameOverride).toHaveBeenCalledWith("display-name:app:explorer.exe", {
      displayName: "Windows 탐색기",
      pattern: "explorer.exe",
      ruleType: "app",
    });

    await user.click(within(await screen.findByRole("row", { name: /Windows 탐색기/ })).getByRole("button", { name: /삭제/ }));

    expect(deleteDisplayNameOverride).toHaveBeenCalledWith("display-name:app:explorer.exe");
    expect(onChanged).toHaveBeenCalled();
  });
});
