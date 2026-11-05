import { activityFor, validPairingToken } from "./activity.js";
import { mascotState, mascotIcon, mascotTitle } from "./mascot.js";

const ENDPOINT = "http://127.0.0.1:47821/v1/activity";
const HEARTBEAT = "monitor-heartbeat";
let queue = Promise.resolve();
let lastMascotState;

// Serialize snapshots so a slower request cannot overwrite a newer tab state.
function enqueue(operation) {
  const next = queue.then(operation, operation);
  queue = next.catch(() => {});
  return next;
}

async function remember(status) {
  const connection = { ...status, checkedAt: Date.now() };
  await chrome.storage.session.set({ connection });
  const state = mascotState(status);
  if (state !== lastMascotState) {
    // Toolbar icons are static. Only a real connection-state change replaces them.
    // Artwork failures must not turn successful tracking into a connection error.
    try {
      await chrome.action.setIcon({ path: Object.fromEntries([16, 24, 32, 48].map(size => [size, mascotIcon(state, size)])) });
      await chrome.action.setTitle({ title: mascotTitle(state) });
      lastMascotState = state;
    } catch { /* Retry on the next snapshot. */ }
  }
  await chrome.action.setBadgeText({ text: status.connected ? "" : "!" });
  await chrome.action.setBadgeBackgroundColor({ color: "#a36b43" });
  return connection;
}

async function send(token, activity) {
  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
    body: JSON.stringify(activity),
    signal: AbortSignal.timeout(4000),
    cache: "no-store",
    credentials: "omit",
    redirect: "error"
  });
  if (response.status === 401) throw new Error("配对码不匹配，请从 Monitor 重新复制。");
  if (!response.ok) throw new Error(`本机服务返回错误（${response.status}）。`);
  const result = await response.json();
  if (result.status !== "ok" || result.version !== 1) throw new Error("本机服务版本不兼容。");
  return result;
}

async function sync() {
  try {
    const { pairingToken } = await chrome.storage.local.get("pairingToken");
    if (!validPairingToken(pairingToken)) {
      return await remember({ connected: false, paired: false, recording: false, error: "请先粘贴本机配对码。" });
    }
    let window = null;
    let tab = null;
    try {
      window = await chrome.windows.getLastFocused({ windowTypes: ["normal"] });
      if (window?.focused && !window.incognito) {
        [tab] = await chrome.tabs.query({ active: true, windowId: window.id });
      }
    } catch {
      // No normal browser window is open. Explicitly clear the last known domain.
    }
    const result = await send(pairingToken, activityFor(window, tab));
    return await remember({ connected: true, paired: true, recording: result.recording, error: null });
  } catch (error) {
    const message = error instanceof TypeError || error.name === "TimeoutError" || error.name === "AbortError"
      ? "连接不到 Monitor。请先打开 Mac 上的应用，稍后重试。"
      : error.message || "连接失败，请重试。";
    return await remember({ connected: false, paired: true, recording: false, error: message });
  }
}

function scheduleSync() { return enqueue(sync); }
function trigger() { void scheduleSync().catch(() => {}); }

async function ensureAlarm() {
  if (!(await chrome.alarms.get(HEARTBEAT))) {
    await chrome.alarms.create(HEARTBEAT, { periodInMinutes: 0.5 });
  }
}

// All listeners are registered synchronously on every worker start.
chrome.tabs.onActivated.addListener(trigger);
chrome.tabs.onUpdated.addListener((_id, change, tab) => {
  if (tab.active && (change.url !== undefined || change.title !== undefined || change.status === "complete")) trigger();
});
chrome.tabs.onRemoved.addListener(trigger);
chrome.tabs.onReplaced.addListener(trigger);
chrome.windows.onFocusChanged.addListener(trigger);
chrome.windows.onRemoved.addListener(trigger);
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === HEARTBEAT) trigger(); });
chrome.runtime.onStartup.addListener(() => { void ensureAlarm().then(trigger).catch(() => {}); });
chrome.runtime.onInstalled.addListener(() => { void ensureAlarm().then(trigger).catch(() => {}); });

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL("popup.html"))) return;
  const operation = async () => {
    if (message?.type === "pair") {
      const token = typeof message.token === "string" ? message.token.trim().toLowerCase() : "";
      if (!validPairingToken(token)) return { connected: false, error: "配对码应为 64 位字符，请完整复制。" };
      await chrome.storage.local.set({ pairingToken: token });
      return sync();
    }
    if (message?.type === "disconnect") {
      const { pairingToken } = await chrome.storage.local.get("pairingToken");
      if (validPairingToken(pairingToken)) {
        try { await send(pairingToken, { focused: false, domain: null }); } catch {}
      }
      await chrome.storage.local.remove("pairingToken");
      return remember({ connected: false, paired: false, recording: false, error: "已断开，网站记录已停止。" });
    }
    if (message?.type === "status") return sync();
    return { connected: false, error: "未知操作。" };
  };
  enqueue(operation).then(respond, () => respond({ connected: false, error: "扩展暂时不可用，请重新加载。" }));
  return true;
});

// Chrome can discard alarms across restarts. Recreate a missing alarm whenever the worker wakes.
void chrome.storage.local.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" }).catch(() => {});
void ensureAlarm().then(trigger).catch(() => {});
