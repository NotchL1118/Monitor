import AppKit
import SwiftUI
import XCTest
import MonitorCore
@testable import Monitor

final class ReportControlsTests: XCTestCase {
    func testWeekAndMonthAcrossYearBoundary() throws {
        var calendar = ReportPeriod.calendar
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        let jan1 = date(2027, 1, 1)
        XCTAssertEqual(ReportPeriod.week.interval(containing: jan1, calendar: calendar),
                       DateInterval(start: date(2026, 12, 28), end: date(2027, 1, 4)))
        XCTAssertEqual(ReportPeriod.month.interval(containing: jan1, calendar: calendar),
                       DateInterval(start: jan1, end: date(2027, 2, 1)))
        XCTAssertEqual(ReportPeriod.month.interval(containing: date(2028, 2, 29), calendar: calendar).end,
                       date(2028, 3, 1))
        let dstWeek = ReportPeriod.week.interval(containing: date(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(dstWeek.duration, 169 * 3600)
    }

    @MainActor
    func testSidebarRowsRespondToClicksInTrailingPadding() async throws {
        try TestEnvironment.requireWindowRendering()
        _ = NSApplication.shared
        let model = MonitorModel(dataDirectory: FileManager.default.temporaryDirectory)
        let host = NSHostingView(rootView: DashboardView().environmentObject(model)
            .environment(\.accessibilityEnabled, true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 650),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        func button(named title: String, in item: NSObject) -> NSObject? {
            if item.responds(to: NSSelectorFromString("accessibilityRole")),
               item.value(forKey: "accessibilityRole") as? String == "AXButton",
               item.value(forKey: "accessibilityLabel") as? String == title { return item }
            guard item.responds(to: NSSelectorFromString("accessibilityChildren")),
                  let children = item.value(forKey: "accessibilityChildren") as? [NSObject] else { return nil }
            return children.lazy.compactMap { button(named: title, in: $0) }.first
        }

        let destinations: [(String, DashboardPage)] = [
            ("应用分析", .applications), ("浏览器分析", .browser), ("一日时间线", .dayTimeline),
            ("连接与设置", .connection), ("时间概览", .overview)
        ]
        for (title, destination) in destinations {
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let row = try XCTUnwrap(button(named: title, in: host), title)
            let frame = try XCTUnwrap(row.value(forKey: "accessibilityFrame") as? NSValue)
            let rect = window.convertFromScreen(frame.rectValue)
            let page = try XCTUnwrap(scrollViews(in: host).first)
            // Click just inside the row, measured from the sidebar's 20-point outer margin.
            let sidebarRight = page.convert(page.bounds, to: nil).minX
            try click(in: window, at: CGPoint(x: sidebarRight - 24, y: rect.midY))
            XCTAssertEqual(model.dashboardPage, destination, title)
        }
    }

    @MainActor
    private func click(in window: NSWindow, at location: CGPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    @MainActor
    func testOverviewLimitsPreviewAndRestoresScrollAfterClosingRanking() async throws {
        try TestEnvironment.requireWindowRendering()
        _ = NSApplication.shared
        let model = MonitorModel(dataDirectory: FileManager.default.temporaryDirectory)
        let websites = (1...200).map { UsageSummary(key: "site-\($0)", name: "site-\($0)", seconds: Double(205 - $0)) }
        model.websites = Array(websites.prefix(1))
        var cardRect = CGRect.zero
        let root = DashboardView().environmentObject(model)
            .overlayPreferenceValue(OverviewModuleBounds.self) { bounds in
                GeometryReader { geometry in
                    if let anchor = bounds[.ranking(.website)] {
                        Color.clear.onChange(of: geometry[anchor], initial: true) { _, rect in cardRect = rect }
                    }
                }.allowsHitTesting(false)
            }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 650),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
        }
        func click(_ point: CGPoint) throws {
            let y = host.isFlipped ? point.y : host.bounds.height - point.y
            let location = host.convert(CGPoint(x: point.x, y: y), to: nil)
            try self.click(in: window, at: location)
        }

        try await settle()
        let page = try XCTUnwrap(scrollViews(in: host).first)
        let document = try XCTUnwrap(page.documentView)
        var previousHeight = document.frame.height
        for count in 2...5 {
            model.websites = Array(websites.prefix(count))
            try await settle()
            XCTAssertGreaterThan(document.frame.height, previousHeight)
            previousHeight = document.frame.height
        }
        let fiveRows = document.frame.height
        model.websites = websites
        try await settle()
        XCTAssertEqual(document.frame.height, fiveRows, accuracy: 1)
        page.contentView.scroll(to: NSPoint(x: 0, y: 110))
        try await settle()
        let offset = page.contentView.bounds.origin
        XCTAssertFalse(cardRect.isEmpty)
        try click(CGPoint(x: cardRect.midX, y: cardRect.midY))
        try await Task.sleep(for: .milliseconds(550))
        let list = try XCTUnwrap(scrollViews(in: host).first { $0 !== page })
        list.contentView.scroll(to: NSPoint(x: 0, y: 200))
        XCTAssertGreaterThan(list.contentView.bounds.origin.y, 0)
        XCTAssertEqual(page.contentView.bounds.origin, offset)
        func searchField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.placeholderString == "搜索网站域名" { return field }
            return view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        let search = try XCTUnwrap(searchField(in: host))
        XCTAssertTrue(window.makeFirstResponder(search))
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        editor.insertText("SITE-200", replacementRange: editor.selectedRange())
        try await settle()
        let filtered = try XCTUnwrap(scrollViews(in: host).first { $0 !== page })
        XCTAssertLessThanOrEqual(try XCTUnwrap(filtered.documentView).frame.height, filtered.bounds.height + 1)
        try click(CGPoint(x: 30, y: host.bounds.midY))
        for _ in 0..<20 where scrollViews(in: host).count != 1 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(scrollViews(in: host).count, 1)
        XCTAssertEqual(page.contentView.bounds.origin, offset)
        XCTAssertEqual(document.frame.height, fiveRows, accuracy: 1)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? [])
            + view.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor
    func testWheelOverRankingScrollsThePage() async throws {
        try TestEnvironment.requireWindowRendering()
        _ = NSApplication.shared
        let items = (1...20).map {
            UsageSummary(key: "site-\($0)", name: "site-\($0)", seconds: Double(21 - $0))
        }
        let root = ScrollView {
            RankingCard(kind: .website, items: items)
            Color.clear.frame(height: 800)
        }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()

        let scrollers = scrollViews(in: host)
        XCTAssertEqual(scrollers.count, 1)
        let page = try XCTUnwrap(scrollers.first)
        let start = page.contentView.bounds.origin
        let point = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        let hit = try XCTUnwrap(host.hitTest(point))
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                          wheel1: -4, wheel2: 0, wheel3: 0))
        hit.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotEqual(page.contentView.bounds.origin, start)
    }
}
