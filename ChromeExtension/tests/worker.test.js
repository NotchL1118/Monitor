import test from "node:test";
import assert from "node:assert/strict";

test("worker pairs, sends private snapshots, survives network failure, and disconnects", async () => {
  const event = () => ({ listeners: [], addListener(fn) { this.listeners.push(fn); } });
  const storage = () => ({
    data: {}, async get(key) { return { [key]: this.data[key] }; },
    async set(value) { Object.assign(this.data, value); }, async remove(key) { delete this.data[key]; },
    async setAccessLevel() {}
  });
  const id = "a".repeat(32);
  let focused = true;
  let online = true;
  let recording = true;
  let iconFails = false;
  const icons = [];
  const titles = [];
  let activeTab = { active: true, url: "https://www.youtube.com/watch?v=private", title: "Video one" };
  const requests = [];
  globalThis.chrome = {
    storage: { local: storage(), session: storage() },
    action: {
      async setBadgeText() {}, async setBadgeBackgroundColor() {},
      async setIcon(value) { if (iconFails) throw new Error("Icon unavailable"); icons.push(value.path); },
      async setTitle(value) { titles.push(value.title); }
    },
    tabs: {
      onActivated: event(), onUpdated: event(), onRemoved: event(), onReplaced: event(),
      async query() { return [activeTab]; }
    },
    windows: {
      onFocusChanged: event(), onRemoved: event(),
      async getLastFocused() { return { id: 1, focused, type: "normal" }; }
    },
    alarms: { alarm: null, onAlarm: event(), async get() { return this.alarm; }, async create(name, value) { this.alarm = { name, ...value }; } },
    runtime: { id, onStartup: event(), onInstalled: event(), onMessage: event(), getURL(path) { return `chrome-extension://${id}/${path}`; } }
  };
  globalThis.fetch = async (url, options) => {
    if (!online) throw new TypeError("Failed to fetch");
    requests.push({ url, options, activity: JSON.parse(options.body) });
    return { status: 200, ok: true, async json() { return { status: "ok", version: 1, recording }; } };
  };
  await import("../background.js");
  const message = value => new Promise(resolve => {
    chrome.runtime.onMessage.listeners[0](value, { id, url: chrome.runtime.getURL("popup.html") }, resolve);
  });
  assert.equal((await message({ type: "status" })).paired, false);
  assert.equal(icons.at(-1)[16], "icons/monitor-waiting-16.png");
  assert.equal(chrome.alarms.alarm.periodInMinutes, 0.5);
  const paired = await message({ type: "pair", token: "b".repeat(64) });
  assert.equal(paired.connected, true);
  assert.equal(icons.at(-1)[16], "icons/monitor-16.png");
  const iconCount = icons.length;
  await message({ type: "status" });
  assert.equal(icons.length, iconCount, "unchanged tracking state must not refresh the toolbar image");
  assert.equal(requests.at(-1).url, "http://127.0.0.1:47821/v1/activity");
  assert.deepEqual(requests.at(-1).activity, { focused: true, domain: "www.youtube.com", url: activeTab.url, title: "Video one" });
  assert.equal(requests.at(-1).options.headers.Authorization, `Bearer ${"b".repeat(64)}`);
  const waitForSend = async before => {
    for (let attempt = 0; attempt < 30 && requests.length === before; attempt++) await new Promise(r => setTimeout(r, 5));
    assert.ok(requests.length > before);
  };
  let before = requests.length;
  activeTab = { ...activeTab, title: "Updated title" };
  chrome.tabs.onUpdated.listeners[0](1, { title: activeTab.title }, activeTab);
  await waitForSend(before);
  assert.equal(requests.at(-1).activity.title, "Updated title");
  before = requests.length;
  activeTab = { ...activeTab, url: "https://www.youtube.com/watch?v=second" };
  chrome.tabs.onUpdated.listeners[0](1, { url: activeTab.url }, activeTab);
  await waitForSend(before);
  assert.equal(requests.at(-1).activity.url, activeTab.url);
  assert.deepEqual(Object.keys(chrome.storage.local.data), ["pairingToken"]);
  assert.equal(JSON.stringify(chrome.storage.session.data).includes("youtube"), false);
  focused = false;
  chrome.windows.onFocusChanged.listeners[0](-1);
  await message({ type: "status" });
  assert.deepEqual(requests.at(-1).activity, { focused: false, domain: null });
  online = false;
  assert.equal((await message({ type: "status" })).connected, false);
  assert.equal(icons.at(-1)[32], "icons/monitor-waiting-32.png");
  online = true;
  assert.equal((await message({ type: "status" })).connected, true);
  recording = false;
  iconFails = true;
  assert.equal((await message({ type: "status" })).connected, true, "a failed icon update must not break tracking");
  iconFails = false;
  assert.equal((await message({ type: "status" })).recording, false);
  assert.equal(icons.at(-1)[24], "icons/monitor-sleeping-24.png");
  assert.match(titles.at(-1), /已暂停/);
  recording = true;
  await message({ type: "status" });
  assert.equal(icons.at(-1)[48], "icons/monitor-48.png");
  assert.equal((await message({ type: "disconnect" })).paired, false);
  assert.equal(chrome.storage.local.data.pairingToken, undefined);
  assert.deepEqual(requests.at(-1).activity, { focused: false, domain: null });
});
