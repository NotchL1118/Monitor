// One state mapping for the toolbar and popup; no website data enters the artwork.
export function mascotState(status) {
  if (!status?.connected) return "waiting";
  return status.recording ? "awake" : "sleeping";
}

export function mascotIcon(state, size) {
  return `icons/monitor-${state === "awake" ? "" : `${state}-`}${size}.png`;
}

export function mascotTitle(state) {
  return `Monitor · ${state === "awake" ? "正在记录" : state === "sleeping" ? "记录已暂停" : "尚未连接"}`;
}
