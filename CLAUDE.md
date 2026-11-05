# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Monitor is a native macOS 14+ menu-bar time tracker (Swift 5.9 / SwiftUI / system SQLite, no third-party packages), plus a companion Chrome Manifest V3 extension in `ChromeExtension/` that reports the active tab to the app. All data stays local. UI strings, README and error messages are in Simplified Chinese; keep new user-facing text consistent with that.

## Commands

Always go through the scripts (or replicate their env vars). They set `CLANG_MODULE_CACHE_PATH`/`SWIFTPM_MODULECACHE_OVERRIDE` to `.build/ModuleCache` and pass `--disable-sandbox --cache-path .build/cache`.

```bash
./scripts/build.sh          # regenerate icons/brand PNGs, release build, assemble + ad-hoc sign dist/Monitor.app
open dist/Monitor.app
./scripts/test.sh           # swift test + node --test ChromeExtension/tests/*.test.js
```

Run a single Swift test (use the same env/flags):

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift test --disable-sandbox --cache-path .build/cache --filter MonitorCoreTests.SessionMergerTests
swift test --disable-sandbox --cache-path .build/cache --filter MonitorCoreTests.TrackingTests/testName
```

Extension tests only: `node --test ChromeExtension/tests/*.test.js` (Node 18+, no npm install).

Test notes:
- `MonitorAppTests/IntegrationTests` starts the real `MonitorModel`, binds `127.0.0.1:47821` and renders SwiftUI. It needs a desktop session, and the running Monitor app must be quit first (port conflict). It writes a screenshot to `.build/qa/dashboard.png`.
- An optional real-browser test is `node scripts/test-chrome.mjs`. It requires `PLAYWRIGHT_MODULE_PATH` and `CHROME_TEST_EXECUTABLE` (Chrome for Testing).

## Architecture

SwiftPM targets (`Package.swift`):
- `CSQLite`: system-library shim that links `libsqlite3`.
- `MonitorCore`: pure, testable logic with no AppKit. It has four parts:
  - `ActivityTracker` (`Activity.swift`): a value-type state machine. Callers set the current app or browser state and call `advance(to:)`, which returns `ActivitySlice`s for the elapsed interval.
  - `ActivityStore`: SQLite in WAL mode. It has one `activities` table and runs schema migrations in `init` by adding nullable columns.
  - `HTTPRequest` (`LocalProtocol.swift`): a minimal HTTP parser and auth check.
  - `SessionMerger`: display-only merging of short switches.
- `Monitor` (executable): AppKit/SwiftUI shell. `MonitorModel.shared` is the `@MainActor` hub. It owns the store, tracker, `LocalServer`, the 5 s sampling timer and the sleep/lock/session observers, and it publishes all report state that the views read.

Data flow: NSWorkspace activation, timer ticks and browser POSTs each call `persist(until:)` (`tracker.advance` then `store.record`) *before* changing tracker state. The model then calls `refresh()`, which re-queries the store for the selected `ReportPeriod`/`ReportTimeZone`. Report structs (`ApplicationReport`, `DayTimelineReport`, `TodaySnapshot`) are built from store queries and drive the views.

Invariants that span files:
- **App and website time are separate dimensions.** A website slice is emitted only while the frontmost app is `com.google.Chrome` and the last browser update is less than `browserTTL` (75 s) old. Website time is never added to app totals.
- **Gaps above `maximumGap` (60 s) are dropped.** Sleep, lock, display sleep, session changes and `loginwindow` suspend tracking through `suspensionReasons`. App Nap is disabled so the 5 s timer isn't throttled.
- **Raw slices are never rewritten.** `SessionMerger` (30 s threshold) only affects the timeline and app-detail display ("含 N 次短暂切换"). Totals, hourly curves and JSON export must use the raw slices.
- **Day boundaries come from the selected `ReportTimeZone`** (system or fixed UTC+8). Slices are clipped at calendar boundaries, and DST matters. Timestamps are stored and exported in UTC.
- **The local server binds only to `127.0.0.1:47821`.** It requires a `Bearer` pairing token (64 hex chars, stored in `~/Library/Application Support/Monitor/pairing-token` with mode 0600) and validates Host and Origin. Request limits are 64 KB body and 8 KB headers. Timestamps are always assigned by the app, never taken from the extension. `BrowserUpdate.isValid` enforces the URL/title rules (http(s) only, host must match the domain, no credentials, URL ≤ 8 KB, title ≤ 1 KB). The README documents the protocol.

Chrome extension: `activity.js` holds pure functions shared by the service worker (`background.js`) and the Node tests. `mascot.js` holds the icon/state logic. The popup handles pairing. Bump the extension version together with the app version.

Brand assets: `Sources/Monitor/MascotArtwork.swift` is the single drawing source for the small mascot. `build.sh` compiles it together with `scripts/make-brand-assets.swift` to generate the Chrome icon PNGs, and `scripts/make-icon.swift` generates the app icon. Don't hand-edit generated icons. `dist/` and `.build/` are build output.
