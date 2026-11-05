import { mascotState, mascotIcon } from "./mascot.js";

const title = document.querySelector("#status-title");
const detail = document.querySelector("#status-detail");
const dot = document.querySelector("#dot");
const token = document.querySelector("#token");
const disconnect = document.querySelector("#disconnect");
const mascot = document.querySelector("#mascot");

function render(result) {
  const connected = Boolean(result?.connected);
  const state = mascotState(result);
  mascot.src = mascotIcon(state, 256);
  mascot.dataset.state = state;
  title.textContent = connected ? (result.recording ? "已连接 · 正在记录" : "已连接 · 记录已暂停") : "尚未连接";
  detail.textContent = connected
    ? (result.recording ? "当前前台网页会自动记入本机时间足迹。" : "在 Mac 上的 Monitor 中恢复记录。")
    : result?.error || "请打开 Monitor，再检查一次。";
  dot.classList.toggle("connected", connected && Boolean(result.recording));
  disconnect.hidden = !result?.paired;
  token.placeholder = result?.paired ? "配对码已保存；输入新码可更换" : "从 Monitor「连接与设置」中复制";
}

async function request(message) {
  for (const button of document.querySelectorAll("button")) button.disabled = true;
  try {
    const result = await chrome.runtime.sendMessage(message);
    render(result);
    if (message.type === "pair" && result?.connected) token.value = "";
  } catch {
    render({ error: "扩展未能响应，请在扩展管理页重新加载。" });
  } finally {
    for (const button of document.querySelectorAll("button")) button.disabled = false;
  }
}

document.querySelector("#pair-form").addEventListener("submit", event => {
  event.preventDefault();
  void request(token.value.trim() ? { type: "pair", token: token.value } : { type: "status" });
});
document.querySelector("#refresh").addEventListener("click", () => { void request({ type: "status" }); });
disconnect.addEventListener("click", () => { void request({ type: "disconnect" }); });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "session" && changes.connection?.newValue) render(changes.connection.newValue);
});
void request({ type: "status" });
