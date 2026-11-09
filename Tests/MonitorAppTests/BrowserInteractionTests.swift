import AppKit
import SwiftUI
import XCTest
import MonitorCore
@testable import Monitor

final class BrowserInteractionTests: XCTestCase {
    @MainActor
    func testWholeHeaderTogglesAndBothViewsShareSelectionAcrossMinutes() async throws {
        try TestEnvironment.requireWindowRendering()
        _ = NSApplication.shared
        let calendar = ReportTimeZone.utcPlus8.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, minute: 11))!
        let session = ActivitySlice(id: 1, kind: .application, key: ActivityTracker.chromeBundleID, name: "Chrome",
                                    start: start, end: start.addingTimeInterval(120))
        let spans: [(Double, Double)] = [(0, 3), (10, 34), (47, 70), (70, 79.894), (80, 95), (119.7, 120)]
        let visits = spans.enumerated().map { index, span in
            let domain = index < 2 ? "video.test" : "docs.test"
            return ActivitySlice(id: Int64(index + 2), kind: .website, key: domain, name: domain,
                                 start: start.addingTimeInterval(span.0), end: start.addingTimeInterval(span.1),
                                 pageURL: "https://\(domain)/" + (index == 2 ? "" : "page"),
                                 pageTitle: index < 2 ? "视频首页" : (index == 2 ? "文档首页" : "接口文档 · 请求与响应"))
        }
        struct Fixture: View {
            let session: ActivitySlice
            let visits: [ActivitySlice]
            let calendar: Calendar
            @State private var mode = BrowserDetailMode.list

            var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("详细时间段").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        BrowserViewSwitcher(selection: $mode)
                    }
                    BrowserSessionView(session: session, visits: visits, calendar: calendar, mode: mode, scrollProxy: nil,
                                       activeSeconds: 120, interruptions: 0, initiallyExpanded: false, highlighted: false)
                }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundStyle(Palette.ink).background(.white).preferredColorScheme(.light)
                    .environment(\.accessibilityEnabled, true)
            }
        }
        let host = NSHostingView(rootView: Fixture(session: session, visits: visits, calendar: calendar))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
        }
        // SwiftUI's virtual accessibility elements expose AppKit selectors without formal protocol conformance.
        func attribute(_ item: NSObject, _ name: String) -> Any? {
            item.responds(to: NSSelectorFromString(name)) ? item.value(forKey: name) : nil
        }
        func elements(_ item: NSObject) -> [NSObject] {
            [item] + (attribute(item, "accessibilityChildren") as? [NSObject] ?? []).flatMap(elements)
        }
        func element(_ identifier: String) throws -> NSObject {
            try XCTUnwrap(elements(host).first { attribute($0, "accessibilityIdentifier") as? String == identifier }, identifier)
        }
        func selected(_ identifier: String) throws -> Bool {
            attribute(try element(identifier), "isAccessibilitySelected") as? Bool == true
        }
        func click(_ item: NSObject, at fraction: CGFloat = 0.5) throws {
            let frame = try XCTUnwrap(attribute(item, "accessibilityFrame") as? NSValue)
            let rect = window.convertFromScreen(frame.rectValue)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: rect.minX + rect.width * fraction, y: rect.midY),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
        }
        func capture(_ name: String) throws {
            let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let output = project.appendingPathComponent(".build/qa")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
        }
        try await settle()
        XCTAssertTrue(try selected("browser-mode-list"))
        try click(element("browser-session-1"), at: 0.96)
        try await settle()
        try click(element("browser-ribbon-3"))
        try await settle()
        XCTAssertTrue(try selected("browser-row-3"))
        XCTAssertTrue(elements(host).contains { attribute($0, "accessibilityLabel") as? String == "复制页面地址" })
        try click(element("browser-session-1"), at: 0.45)
        try await settle()
        XCTAssertFalse(elements(host).contains { attribute($0, "accessibilityIdentifier") as? String == "browser-ribbon-3" })
        try click(element("browser-session-1"), at: 0.2)
        try await settle()
        XCTAssertTrue(try selected("browser-row-3"))
        try capture("browser-session-list.png")
        try click(element("browser-row-5"))
        try await settle()
        XCTAssertTrue(try selected("browser-ribbon-5"))
        try click(element("browser-mode-trace"))
        try await settle()
        XCTAssertTrue(try selected("browser-lane-5"))
        for visit in visits { _ = try element("browser-lane-\(visit.id)") }
        // The first two visits start in the first minute and later visits start in the second.
        // All lanes share one scale and the visit crossing the minute boundary is one control.
        func laneFrame(_ id: Int64) throws -> CGRect {
            let item = try element("browser-lane-\(id)")
            let frame = try XCTUnwrap(attribute(item, "accessibilityFrame") as? NSValue)
            return frame.rectValue
        }
        let first = try laneFrame(2), crossing = try laneFrame(4), last = try laneFrame(6)
        let pointsPerSecond = (last.minX - first.minX) / 80
        XCTAssertGreaterThan(pointsPerSecond, 0)
        XCTAssertEqual(crossing.minX - first.minX, 47 * pointsPerSecond, accuracy: 1)
        XCTAssertEqual(crossing.width, 23 * pointsPerSecond, accuracy: 1)
        // Three visits in a continuous site band remain independently clickable.
        for id in [4, 5, 6] {
            try click(element("browser-lane-\(id)"))
            try await settle()
            XCTAssertTrue(try selected("browser-lane-\(id)"))
        }
        try click(element("browser-lane-4"))
        try await settle()
        try capture("browser-session-trace.png")
        try click(element("browser-mode-list"))
        try await settle()
        XCTAssertTrue(try selected("browser-ribbon-4"))
        XCTAssertTrue(try selected("browser-row-4"))
        window.setContentSize(NSSize(width: 520, height: 480))
        try await settle()
        try capture("browser-session-list-narrow.png")
        try click(element("browser-row-7"))
        try await settle()
        XCTAssertTrue(try selected("browser-ribbon-7"))
        let shortVisit = try element("browser-ribbon-7")
        let shortFrame = try XCTUnwrap(attribute(shortVisit, "accessibilityFrame") as? NSValue)
        XCTAssertLessThan(shortFrame.rectValue.width, 2)
        try capture("browser-session-short-selection.png")
    }
}
