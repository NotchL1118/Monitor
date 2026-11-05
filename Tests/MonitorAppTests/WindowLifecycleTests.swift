import AppKit
import XCTest
@testable import Monitor

final class WindowLifecycleTests: XCTestCase {
    @MainActor
    func testDockFollowsMainWindowAndStatusDashboardSurvivesClosing() async throws {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        let suite = "Monitor-Window-QA-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = MonitorModel(dataDirectory: FileManager.default.temporaryDirectory, preferences: preferences)
        // The test model never starts tracking or opens the user's database.
        let delegate = AppDelegate(model: model)
        let status = StatusController(model: model) { page in delegate.showWindow(page) }
        defer {
            delegate.mainWindow?.close()
            status.stop()
            app.setActivationPolicy(previousPolicy)
            preferences.removePersistentDomain(forName: suite)
        }

        delegate.showWindow(.overview)
        let window = try XCTUnwrap(delegate.mainWindow)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(app.activationPolicy(), .regular)

        window.miniaturize(nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(app.activationPolicy(), .regular)
        delegate.showWindow(.overview)
        // Wait for the system's Dock restore animation before issuing a new close action.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(window.isMiniaturized)

        window.performClose(nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(app.activationPolicy(), .accessory)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(app))
        status.handleClick(secondary: false)
        XCTAssertTrue(model.menuDashboardVisible)
        status.handleClick(secondary: false)
        XCTAssertFalse(model.menuDashboardVisible)

        delegate.showWindow(.connection)
        XCTAssertTrue(delegate.mainWindow === window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(app.activationPolicy(), .regular)
        XCTAssertEqual(model.dashboardPage, .connection)
        window.performClose(nil)
        XCTAssertEqual(app.activationPolicy(), .accessory)

        XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(app.activationPolicy(), .regular)
    }
}
