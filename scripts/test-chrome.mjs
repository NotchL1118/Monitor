// Optional real-browser smoke test. Uses a disposable profile and entirely mocked website pages.
// Set PLAYWRIGHT_MODULE_PATH and CHROME_TEST_EXECUTABLE to an existing Playwright installation
// and Chrome for Testing executable. Does not use or modify your everyday Chrome profile.
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const project = resolve(dirname(fileURLToPath(import.meta.url)), "..");
if (!process.env.PLAYWRIGHT_MODULE_PATH || !process.env.CHROME_TEST_EXECUTABLE) {
  throw new Error("Set PLAYWRIGHT_MODULE_PATH and CHROME_TEST_EXECUTABLE before running the optional browser smoke test.");
}
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE_PATH);
const output = resolve(project, ".build/qa");
await mkdir(output, { recursive: true });
const profile = await mkdtemp(resolve(output, "chrome-profile-"));
const token = randomBytes(32).toString("hex");
const updates = [];
const errors = [];
let recording = true;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate) {
  for (let i = 0; i < 100; i++) { if (predicate()) return; await delay(100); }
  throw new Error("Timed out waiting for extension activity.");
}
const server = createServer((request, response) => {
  let body = "";
  request.on("data", chunk => { body += chunk; });
  request.on("end", () => {
    if (request.headers.authorization !== `Bearer ${token}`) {
      response.writeHead(401, { "Content-Type": "application/json" });
      response.end(JSON.stringify({ status: "pairing_required" }));
      return;
    }
    assert.equal(request.url, "/v1/activity");
    updates.push(JSON.parse(body));
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ status: "ok", version: 1, recording }));
  });
});
await new Promise((resolve, reject) => { server.once("error", reject); server.listen(47821, "127.0.0.1", resolve); });
let context;
try {
  const extension = resolve(project, "ChromeExtension");
  context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.CHROME_TEST_EXECUTABLE,
    headless: true,
    viewport: { width: 344, height: 640 },
    args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`, "--disable-background-networking"]
  });
  const worker = context.serviceWorkers()[0] || await context.waitForEvent("serviceworker", { timeout: 15000 });
  const extensionID = new URL(worker.url()).host;
  const popup = await context.newPage();
  popup.on("pageerror", error => errors.push(error.message));
  await popup.goto(`chrome-extension://${extensionID}/popup.html`);
  await popup.locator("#connect").waitFor();
  await popup.locator("#token").fill(token);
  await popup.locator("#connect").click();
  await popup.getByText("已连接 · 正在记录", { exact: true }).waitFor();
  assert.equal(await popup.locator("#mascot").getAttribute("data-state"), "awake");
  assert.ok(await popup.evaluate(() => [...document.images].every(image => image.complete && image.naturalWidth > 0)));
  assert.ok(await popup.evaluate(() => document.body.getBoundingClientRect().height <= 600), "popup must fit Chrome's height limit");
  await delay(500);
  await popup.locator("body").screenshot({ path: resolve(output, "chrome-popup.png") });
  recording = false;
  await popup.locator("#refresh").click();
  await popup.getByText("已连接 · 记录已暂停", { exact: true }).waitFor();
  assert.equal(await popup.locator("#mascot").getAttribute("data-state"), "sleeping");
  await popup.waitForFunction(async () => (await chrome.action.getTitle({})).includes("已暂停"));
  await popup.locator("body").screenshot({ path: resolve(output, "chrome-popup-paused.png") });
  await popup.locator("#motion").uncheck();
  await popup.waitForFunction(async () => (await chrome.storage.local.get("mascotMotionEnabled")).mascotMotionEnabled === false);
  await popup.reload();
  await popup.getByText("已连接 · 记录已暂停", { exact: true }).waitFor();
  assert.equal(await popup.locator("#motion").isChecked(), false);
  assert.equal(await popup.locator("#mascot").evaluate(element => getComputedStyle(element).animationName), "none");
  await popup.locator("#motion").check();
  await popup.emulateMedia({ reducedMotion: "reduce" });
  assert.equal(await popup.locator("#mascot").evaluate(element => getComputedStyle(element).animationName), "none");
  recording = true;
  await popup.locator("#refresh").click();
  await popup.getByText("已连接 · 正在记录", { exact: true }).waitFor();

  const tab = await context.newPage();
  await tab.route("**/*", route => route.fulfill({ contentType: "text/html", body: "<!doctype html><title>Monitor QA</title><p>Local test fixture</p>" }));
  await tab.goto("https://www.youtube.com/watch?v=private-test-query");
  await tab.bringToFront();
  await until(() => updates.some(update => update.domain === "www.youtube.com" && update.focused));
  await until(() => updates.some(update => update.url === "https://www.youtube.com/watch?v=private-test-query" && update.title === "Monitor QA"));
  await tab.evaluate(() => { document.title = "Renamed page"; history.pushState({}, "", "/watch?v=another#section"); });
  await until(() => updates.some(update => update.title === "Renamed page" && update.url.endsWith("v=another#section")));

  await tab.goto("https://developer.apple.com/documentation?secret=test");
  await until(() => updates.some(update => update.domain === "developer.apple.com"));
  const background = await context.newPage();
  await background.route("**/*", route => route.fulfill({ contentType: "text/html", body: "<title>Background fixture</title>" }));
  await tab.bringToFront();
  await delay(250);
  const beforeBackground = updates.length;
  await background.goto("https://background.test/private");
  await delay(500);
  assert.equal(updates.slice(beforeBackground).some(update => update.domain === "background.test"), false);
  assert.deepEqual(errors, []);
  console.log("Chrome smoke test passed: real MV3 installation, pairing, popup rendering, navigation, page titles, same-domain SPA URLs, and background-tab exclusion.");
} finally {
  if (context) await context.close();
  await new Promise(resolve => server.close(resolve));
  await rm(profile, { recursive: true, force: true });
}
