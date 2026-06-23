import { afterEach, describe, expect, it, vi } from "vitest";
import {
  BRIDGE_HEADER_NAME,
  BRIDGE_HEADER_VALUE,
  reportActiveTabForWindow,
  reportUpdatedActiveTab,
  reportActiveTab,
  sanitizeUrl,
} from "./background";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("sanitizeUrl", () => {
  it("stores domain without path when full URL storage is off", () => {
    expect(sanitizeUrl("https://www.youtube.com/watch?v=abc", false)).toEqual({
      domain: "youtube.com",
      url: undefined,
    });
  });

  it("keeps full URL when enabled", () => {
    expect(sanitizeUrl("https://chatgpt.com/c/123", true)).toEqual({
      domain: "chatgpt.com",
      url: "https://chatgpt.com/c/123",
    });
  });
});

describe("reportActiveTab", () => {
  it("skips unsupported URL schemes", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await reportActiveTab({
      title: "Local file",
      url: "file:///C:/Users/me/private.txt",
    } as chrome.tabs.Tab);

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("sends bridge authentication header", async () => {
    const fetchMock = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("fetch", fetchMock);

    await reportActiveTab({
      title: "ChatGPT",
      url: "https://chatgpt.com/c/123",
    } as chrome.tabs.Tab);

    expect(fetchMock).toHaveBeenCalledWith(
      "http://127.0.0.1:17321/browser-event",
      expect.objectContaining({
        headers: {
          "content-type": "application/json",
          [BRIDGE_HEADER_NAME]: BRIDGE_HEADER_VALUE,
        },
      }),
    );
  });
});

describe("browser activity hooks", () => {
  it("reports the active tab when a browser window gains focus", async () => {
    const fetchMock = vi.fn().mockResolvedValue(undefined);
    const query = vi.fn().mockResolvedValue([
      {
        active: true,
        title: "GitHub",
        url: "https://github.com/openai/codex",
      },
    ]);
    vi.stubGlobal("fetch", fetchMock);
    vi.stubGlobal("chrome", {
      tabs: { query },
      windows: { WINDOW_ID_NONE: -1 },
    });

    await reportActiveTabForWindow(42);

    expect(query).toHaveBeenCalledWith({ active: true, windowId: 42 });
    expect(fetchMock).toHaveBeenCalledOnce();
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toMatchObject({
      domain: "github.com",
      title: "GitHub",
    });
  });

  it("does not report inactive tabs that finish loading in the background", async () => {
    const fetchMock = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("fetch", fetchMock);

    await reportUpdatedActiveTab(
      { status: "complete" },
      {
        active: false,
        title: "Background video",
        url: "https://youtube.com/watch?v=abc",
      } as chrome.tabs.Tab,
    );

    expect(fetchMock).not.toHaveBeenCalled();
  });
});
