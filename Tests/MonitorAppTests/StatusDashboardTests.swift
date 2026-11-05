import AppKit
import XCTest
import MonitorCore
@testable import Monitor

final class StatusDashboardTests: XCTestCase {
    func testTodayTotalsAndRecentChartHaveIndependentBoundaries() throws {
        let store = try ActivityStore(path: ":memory:")
        let midnight = Calendar.current.startOfDay(for: Date())
        let now = midnight.addingTimeInterval(600)
        let start = now.addingTimeInterval(-10800)
        func row(_ kind: ActivityKind, _ key: String, _ a: Date, _ b: Date) -> ActivitySlice {
            ActivitySlice(kind: kind, key: key, name: key, start: a, end: b)
        }
        try store.record([
            row(.application, "editor", start.addingTimeInterval(-300), start.addingTimeInterval(240)),
            row(.application, "chrome", midnight.addingTimeInterval(-60), now.addingTimeInterval(30)),
            row(.website, "example.org", midnight, now)
        ])
        let today = try TodaySnapshot.read(from: store, at: now)
        XCTAssertEqual(today.total, 600)
        XCTAssertEqual(today.apps.map(\.key), ["chrome"])
        XCTAssertEqual(today.browsing, 600)
        XCTAssertEqual(today.bars.first, 240)
        XCTAssertEqual(today.bars[16], 60)
        XCTAssertEqual(today.bars.last, 600)
        XCTAssertEqual(today.bars.reduce(0, +), 900)
    }

    @MainActor
    func testClickTogglesPopoverAndSecondaryClicksOpenNativeMenu() async throws {
        try TestEnvironment.requireWindowRendering()
        _ = NSApplication.shared
        let model = MonitorModel(dataDirectory: FileManager.default.temporaryDirectory)
        let controller = StatusController(model: model) { _ in }
        defer { controller.stop() }
        // Let macOS install the temporary status item before simulating a user click.
        try await Task.sleep(for: .milliseconds(150))
        controller.handleClick(secondary: false)
        XCTAssertTrue(model.menuDashboardVisible)
        controller.handleClick(secondary: false)
        XCTAssertFalse(model.menuDashboardVisible)

        for startsOpen in [false, true] {
            var entries: [String] = []
            let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
                guard let menu = note.object as? NSMenu else { return }
                MainActor.assumeIsolated {
                    entries = menu.items.map(\.title)
                    menu.perform(#selector(NSMenu.cancelTracking), with: nil,
                                 afterDelay: 0.08, inModes: [.eventTracking])
                }
            }
            if startsOpen { controller.handleClick(secondary: false) }
            controller.handleClick(secondary: true)
            NotificationCenter.default.removeObserver(token)
            XCTAssertTrue(entries.contains("连接与设置"))
            XCTAssertTrue(entries.contains("退出 Monitor"))
            XCTAssertFalse(model.menuDashboardVisible)
            controller.handleClick(secondary: false)
            XCTAssertTrue(model.menuDashboardVisible)
            controller.handleClick(secondary: false)
        }
    }
}
