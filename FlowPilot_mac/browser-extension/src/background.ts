export interface SanitizedUrl {
  domain: string;
  url?: string;
}

export const BRIDGE_HEADER_NAME = "x-flowpilot-bridge";
export const BRIDGE_HEADER_VALUE = "flowpilot-browser-bridge-v1";
const OPEN_TABS_ALARM_NAME = "flowpilot-open-tabs";

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
      tabId: tab.id,
      ...payload,
    }),
  }).catch(() => undefined);
}

export async function reportOpenTabs(tabs?: chrome.tabs.Tab[]) {
  const openTabs = tabs ?? await chrome.tabs.query({});
  await Promise.all(openTabs.map((tab) => reportActiveTab(tab)));
}

function scheduleOpenTabsReporting() {
  void chrome.alarms.create(OPEN_TABS_ALARM_NAME, { periodInMinutes: 1 });
  void reportOpenTabs();
}

if (typeof chrome !== "undefined" && chrome.tabs) {
  chrome.tabs.onActivated.addListener(async ({ tabId }) => {
    await reportOpenTabs();
  });

  chrome.tabs.onUpdated.addListener(async (_tabId, changeInfo, tab) => {
    if (changeInfo.status === "complete") {
      await reportOpenTabs();
    }
  });

  if (chrome.alarms) {
    chrome.runtime.onInstalled.addListener(scheduleOpenTabsReporting);
    chrome.runtime.onStartup.addListener(scheduleOpenTabsReporting);
    chrome.alarms.onAlarm.addListener(async (alarm) => {
      if (alarm.name === OPEN_TABS_ALARM_NAME) {
        await reportOpenTabs();
      }
    });
    scheduleOpenTabsReporting();
  }
}
