import test from "node:test";
import assert from "node:assert/strict";
import { activityFor, domainFromTab, validPairingToken } from "../activity.js";

test("domain summary key preserves subdomains and excludes the URL path", () => {
  assert.equal(domainFromTab({ active: true, url: "https://user:secret@WWW.YouTube.COM:443/watch?v=private#fragment" }), "www.youtube.com");
  assert.equal(domainFromTab({ active: true, url: "https://music.youtube.com/" }), "music.youtube.com");
  assert.equal(domainFromTab({ active: true, url: "https://例子.com/" }), "xn--fsqu00a.com");
});

test("ignores inactive, incognito, internal, local-file and malformed pages", () => {
  for (const tab of [
    { active: false, url: "https://example.com" },
    { active: true, incognito: true, url: "https://example.com" },
    ...["chrome://extensions", "about:blank", "file:///secret.txt", "data:text/plain,secret", "not a URL"].map(url => ({ active: true, url }))
  ]) assert.equal(domainFromTab(tab), null);
});

test("only a focused normal browser window contributes website time", () => {
  const tab = { active: true, url: "https://example.com/path" };
  assert.deepEqual(activityFor({ focused: true, type: "normal" }, tab), { focused: true, domain: "example.com", url: "https://example.com/path", title: null });
  for (const window of [null, { focused: false, type: "normal" }, { focused: true, type: "popup" }, { focused: true, type: "normal", incognito: true }]) {
    assert.deepEqual(activityFor(window, tab), { focused: false, domain: null });
  }
});

test("pairing tokens have a strict format", () => {
  assert.equal(validPairingToken("a".repeat(64)), true);
  for (const token of [null, "", "a".repeat(63), "z".repeat(64), "a".repeat(64) + "\n"]) assert.equal(validPairingToken(token), false);
});


test("captures page address and title locally, stripping URL credentials", () => {
  const window = { focused: true, type: "normal" };
  const result = activityFor(window, { active: true, url: "https://user:secret@example.com/path?q=search#route", title: "My page\nTitle" });
  assert.deepEqual(result, { focused: true, domain: "example.com", url: "https://example.com/path?q=search#route", title: "My page Title" });
  const unicode = activityFor(window, { active: true, url: "https://例子.com/path", title: "中".repeat(600) });
  assert.ok(new TextEncoder().encode(unicode.title).length <= 1024);
  assert.equal(unicode.url, "https://xn--fsqu00a.com/path");
  const long = activityFor(window, { active: true, url: "https://example.com/" + "a".repeat(8200), title: "long" });
  assert.deepEqual(long, { focused: true, domain: "example.com" });
  assert.deepEqual(activityFor(window, { active: true, incognito: true, url: "https://example.com/private", title: "private" }), { focused: true, domain: null });
});
