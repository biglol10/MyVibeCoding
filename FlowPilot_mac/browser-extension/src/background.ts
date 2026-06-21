export interface SanitizedUrl {
  domain: string;
  url?: string;
}

export const BRIDGE_HEADER_NAME = "x-flowpilot-bridge";
export const BRIDGE_HEADER_VALUE = "flowpilot-browser-bridge-v1";

export function sanitizeUrl(rawUrl: string, storeFullUrl: boolean): SanitizedUrl {
  const parsed = new URL(rawUrl);
  const domain = parsed.hostname.replace(/^www\./, "");
  return {
    domain,
    url: storeFullUrl ? parsed.toString() : undefined,
  };
}

export async function reportActiveTab(tab: chrome.tabs.Tab) {
  if (!tab.url) {
    return;
  }

  let parsed: URL;
  try {
    parsed = new URL(tab.url);
  } catch {
    return;
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return;
  }

  const payload = sanitizeUrl(parsed.toString(), false);
  await fetch("http://127.0.0.1:17321/browser-event", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      [BRIDGE_HEADER_NAME]: BRIDGE_HEADER_VALUE,
    },
    body: JSON.stringify({
      title: tab.title ?? "",
      ...payload,
    }),
  }).catch(() => undefined);
}

export async function reportActiveTabForWindow(windowId: number) {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    return;
  }

  const [tab] = await chrome.tabs.query({ active: true, windowId });
  if (tab) {
    await reportActiveTab(tab);
  }
}

export async function reportActiveTabForLastFocusedWindow() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (tab) {
    await reportActiveTab(tab);
  }
}

export async function reportUpdatedActiveTab(
  changeInfo: chrome.tabs.OnUpdatedInfo,
  tab: chrome.tabs.Tab,
) {
  if (changeInfo.status === "complete" && tab.active) {
    await reportActiveTab(tab);
  }
}

if (typeof chrome !== "undefined" && chrome.tabs) {
  chrome.tabs.onActivated.addListener(async ({ tabId }) => {
    const tab = await chrome.tabs.get(tabId);
    await reportActiveTab(tab);
  });

  chrome.tabs.onUpdated.addListener(async (_tabId, changeInfo, tab) => {
    await reportUpdatedActiveTab(changeInfo, tab);
  });

  chrome.windows?.onFocusChanged?.addListener(async (windowId) => {
    await reportActiveTabForWindow(windowId);
  });

  chrome.runtime?.onStartup?.addListener(async () => {
    await reportActiveTabForLastFocusedWindow();
  });
}
