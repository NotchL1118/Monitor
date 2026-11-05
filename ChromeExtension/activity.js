// These pure functions are shared by the worker and the regression tests.
export function domainFromTab(tab) {
  if (!tab || tab.incognito || !tab.active || !tab.url) return null;
  try {
    const url = new URL(tab.url);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    const domain = url.hostname.toLowerCase().replace(/\.$/, "");
    // The domain remains the summary key; page details are a separate field.
    if (domain.length > 253 || !domain.split(".").every(label =>
      label.length > 0 && label.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label))) return null;
    return domain;
  } catch { return null; }
}

export function activityFor(window, tab) {
  const focused = Boolean(window?.focused && window.type === "normal" && !window.incognito);
  const domain = focused ? domainFromTab(tab) : null;
  if (!domain) return { focused, domain: null };
  const page = new URL(tab.url);
  // Keep the actual address (including query/hash routes), but never URL credentials.
  page.username = "";
  page.password = "";
  page.hostname = domain;
  if (new TextEncoder().encode(page.href).length > 8192) return { focused, domain };
  const clean = tab.status !== "loading" && typeof tab.title === "string" ? tab.title.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").trim() : "";
  let title = "", bytes = 0;
  for (const char of clean) {
    bytes += new TextEncoder().encode(char).length;
    if (bytes > 1024) break;
    title += char;
  }
  return { focused, domain, url: page.href, title: title || null };
}

export function validPairingToken(token) {
  return typeof token === "string" && token.length === 64 && /^[a-f0-9]{64}$/.test(token);
}
