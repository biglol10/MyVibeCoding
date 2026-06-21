import { afterEach, describe, expect, it, vi } from "vitest";
import {
  BRIDGE_HEADER_NAME,
  BRIDGE_HEADER_VALUE,
  reportActiveTab,
  reportOpenTabs,
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
      id: 42,
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
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({
      domain: "chatgpt.com",
      tabId: 42,
      title: "ChatGPT",
    });
  });

  it("reports every open http tab", async () => {
    const fetchMock = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("fetch", fetchMock);

    await reportOpenTabs([
      { id: 1, title: "YouTube", url: "https://youtube.com/watch?v=abc" },
      { id: 2, title: "Local file", url: "file:///C:/private.txt" },
      { id: 3, title: "Naver", url: "https://www.naver.com/" },
    ] as chrome.tabs.Tab[]);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({
      domain: "youtube.com",
      tabId: 1,
      title: "YouTube",
    });
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({
      domain: "naver.com",
      tabId: 3,
      title: "Naver",
    });
  });
});
