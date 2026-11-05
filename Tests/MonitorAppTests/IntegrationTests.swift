import AppKit
import SwiftUI
import XCTest
import MonitorCore
@testable import Monitor

final class IntegrationTests: XCTestCase {
    @MainActor
    func testNativeAppLocalBridgePersistenceAndRendering() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Monitor-QA-\(UUID().uuidString)")
        let preferenceSuite = "Monitor-Integration-QA-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferenceSuite))
        defer { preferences.removePersistentDomain(forName: preferenceSuite) }
        let model = MonitorModel(dataDirectory: directory, preferences: preferences)
        model.paused = false
        model.start()
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<30 {
            if model.serverReady || model.serverError != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(model.storageError)
        XCTAssertNil(model.serverError)
        XCTAssertTrue(model.serverReady)
        XCTAssertEqual(model.pairingToken.count, 64)

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:47821/v1/status")!)
        request.timeoutInterval = 5
        let (_, unauthorized) = try await session.data(for: request)
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)
        request.setValue("Bearer \(model.pairingToken)", forHTTPHeaderField: "Authorization")
        let (body, authorized) = try await session.data(for: request)
        XCTAssertEqual((authorized as? HTTPURLResponse)?.statusCode, 200)
        let status = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(status["recording"] as? Bool, model.recording)

        request.url = URL(string: "http://127.0.0.1:47821/v1/activity")!
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"domain":"example.test","focused":true}"#.utf8)
        let (_, posted) = try await session.data(for: request)
        XCTAssertEqual((posted as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(model.browserConnected)

        request.httpBody = Data(#"{"domain":"example.test","focused":true,"url":"https://example.test/article?q=local","title":"A local page"}"#.utf8)
        let (_, pagePosted) = try await session.data(for: request)
        XCTAssertEqual((pagePosted as? HTTPURLResponse)?.statusCode, 200)
        request.httpBody = Data(#"{"domain":"example.test","focused":true,"url":"https://wrong.test/","title":"Wrong host"}"#.utf8)
        let (_, wrongHost) = try await session.data(for: request)
        XCTAssertEqual((wrongHost as? HTTPURLResponse)?.statusCode, 400)

        request.httpBody = Data(#"{"domain":"example.test/private?secret=1","focused":true}"#.utf8)
        let (_, invalid) = try await session.data(for: request)
        XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode, 400)

        // Seed only the isolated QA database, never the user's history.
        let db = try ActivityStore(path: directory.appendingPathComponent("activity.sqlite").path)
        let today = model.selectedDate
        let calendar = ReportPeriod.calendar
        let jan1 = calendar.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        let jan5 = calendar.date(byAdding: .day, value: 4, to: jan1)!
        try db.record([
            ActivitySlice(kind: .application, key: "editor", name: "Editor",
                          start: jan1.addingTimeInterval(-60), end: jan1.addingTimeInterval(60)),
            ActivitySlice(kind: .application, key: "editor", name: "Editor",
                          start: jan5, end: jan5.addingTimeInterval(120))
        ])
        model.selectedDate = jan1
        model.selectedApplication = ActivityIdentity(key: "editor", name: "Editor")
        XCTAssertEqual(model.appSeconds, 60)
        XCTAssertEqual(model.applicationReport?.seconds, 60)
        model.period = .week
        XCTAssertEqual(model.appSeconds, 120)
        XCTAssertEqual(model.applicationReport?.seconds, 120)
        model.period = .month
        XCTAssertEqual(model.appSeconds, 180)
        XCTAssertEqual(model.applicationReport?.seconds, 180)
        XCTAssertEqual(model.applicationReport?.sessions.count, 2)
        XCTAssertEqual(model.timeline.count, 2)
        model.reportTimeZone = .utcPlus8
        XCTAssertEqual(model.appSeconds, 240)
        XCTAssertEqual(model.applicationReport?.seconds, 240)
        XCTAssertEqual(model.applicationReport?.calendar.timeZone.secondsFromGMT(), 28800)
        model.reportTimeZone = .system
        XCTAssertEqual(model.appSeconds, 180)
        model.period = .day
        model.selectedDate = today
        XCTAssertEqual(model.applicationReport?.seconds, 0)
        model.selectedApplication = nil
        XCTAssertNil(model.applicationReport)
        model.selectedDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let start = model.reportInterval.start.addingTimeInterval(9 * 3600)
        try db.record([
            ActivitySlice(kind: .application, key: "com.google.Chrome", name: "Google Chrome", start: start, end: start.addingTimeInterval(1200)),
            ActivitySlice(kind: .website, key: "www.youtube.com", name: "www.youtube.com", start: start, end: start.addingTimeInterval(450), pageURL: "https://www.youtube.com/watch?v=sample-one", pageTitle: "设计与专注：把时间看清楚"),
            ActivitySlice(kind: .website, key: "www.youtube.com", name: "www.youtube.com", start: start.addingTimeInterval(450), end: start.addingTimeInterval(900), pageURL: "https://www.youtube.com/watch?v=sample-two", pageTitle: "A calmer desktop — 界面设计分享"),
            ActivitySlice(kind: .website, key: "developer.apple.com", name: "developer.apple.com", start: start.addingTimeInterval(900), end: start.addingTimeInterval(1200)),
            ActivitySlice(kind: .application, key: "com.apple.dt.Xcode", name: "Xcode", start: start.addingTimeInterval(1200), end: start.addingTimeInterval(2100)),
            ActivitySlice(kind: .application, key: "com.apple.finder", name: "Finder", start: start.addingTimeInterval(2100), end: start.addingTimeInterval(2250))
        ])
        model.refresh()
        XCTAssertEqual(model.websites.count, 2)
        XCTAssertEqual(model.websiteSeconds, 1200, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(model.appSeconds, model.websiteSeconds)

        // Present a representative running state when the test host itself is locked.
        model.screenUnavailable = false
        model.currentApp = "Google Chrome"

        let root = DashboardView().environmentObject(model)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 300_000_000)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10000)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = project.appendingPathComponent(".build/qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent("dashboard.png"))

        model.showApplication(ActivityIdentity(key: "com.google.Chrome", name: "Google Chrome"))
        XCTAssertEqual(model.dashboardPage, .applications)
        XCTAssertEqual(model.applicationReport?.seconds, 1200)
        for width in [1120, 920] {
            window.setContentSize(NSSize(width: width, height: 950))
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("detail-dashboard-\(width).png"))
        }
        // Render the approved daily tracks with sparse, long, and very short sessions.
        let fixture: [(String, String, Double, Double)] = [
            ("com.openai.codex", "ChatGPT", 10, 11.5),
            ("com.apple.dt.Xcode", "Xcode", 11.5, 12),
            ("com.google.Chrome", "Google Chrome", 13.5, 14.25),
            ("com.apple.dt.Xcode", "Xcode", 14.25, 15.5),
            ("com.tencent.xinWeChat", "微信", 15.5, 15.52),
            ("com.openai.codex", "ChatGPT", 15.52, 15.54),
            ("com.tencent.xinWeChat", "微信", 15.54, 15.6),
            ("com.openai.codex", "ChatGPT", 15.6, 17.25),
            ("com.google.Chrome", "Google Chrome", 20, 21)
        ]
        let day = model.reportInterval.start
        try db.record(fixture.map { key, name, a, b in
            ActivitySlice(kind: .application, key: key, name: name, start: day.addingTimeInterval(a * 3600), end: day.addingTimeInterval(b * 3600))
        })
        model.refresh()
        model.dashboardPage = .dayTimeline
        XCTAssertEqual(model.dailyActivities.count, 12)
        for width in [1120, 920] {
            window.setContentSize(NSSize(width: width, height: 1200))
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            try XCTUnwrap(image.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("day-timeline-\(width).png"))
        }
        try db.deleteAll()
        model.refresh()
        XCTAssertEqual(model.applicationReport?.seconds, 0)
        XCTAssertTrue(model.applicationReport?.sessions.isEmpty == true)
        model.reportTimeZone = .utcPlus8
        model.dashboardPage = .connection
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let settings = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: settings)
        try XCTUnwrap(settings.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("timezone-settings.png"))
    }
}
