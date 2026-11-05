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
    func testRankingScrollStaysInsideCardAtBothEdges() async throws {
        _ = NSApplication.shared
        let rows = VStack { ForEach(0..<30) { i in Text("应用 \(i)").frame(height: 32) } }
        let card = RankingCardSurface(rows: rows)
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 400))
        outer.hasVerticalScroller = true
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 1400))
        outer.documentView = page
        card.frame = NSRect(x: 0, y: 100, width: 400, height: 302)
        page.addSubview(card)
        let window = NSWindow(contentRect: outer.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = outer
        window.orderFront(nil)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let clip = card.scroller.contentView
        XCTAssertGreaterThan(card.document.frame.height, clip.bounds.height)
        outer.contentView.scroll(to: NSPoint(x: 0, y: 100))
        let outerStart = outer.contentView.bounds.origin
        func wheel(_ delta: Int32, at point: NSPoint = NSPoint(x: 100, y: 100)) throws -> Bool {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                          wheel1: delta, wheel2: 0, wheel3: 0))
            return card.handleWheel(try XCTUnwrap(NSEvent(cgEvent: cg)), at: point)
        }
        XCTAssertTrue(try wheel(-10000))
        let bottom = clip.bounds.origin.y
        XCTAssertGreaterThan(bottom, 300)
        XCTAssertTrue(try wheel(-10000))
        XCTAssertEqual(clip.bounds.origin.y, bottom)
        XCTAssertEqual(outer.contentView.bounds.origin, outerStart)
        XCTAssertTrue(try wheel(10000))
        XCTAssertEqual(clip.bounds.origin.y, 0, accuracy: 1)
        XCTAssertTrue(try wheel(10000))
        XCTAssertEqual(outer.contentView.bounds.origin, outerStart)
        XCTAssertFalse(try wheel(-40, at: NSPoint(x: -10, y: 100)))
        func gesture(_ phase: NSEvent.Phase, at point: NSPoint) throws -> Bool {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                          wheelCount: 1, wheel1: -60, wheel2: 0, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase == .began ? 1 : (phase == .changed ? 2 : 4))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(event.phase, phase)
            let consumed = card.handleWheel(event, at: point)
            return consumed
        }
        let inside = NSPoint(x: 100, y: 100)
        let outside = NSPoint(x: card.bounds.maxX + 20, y: 100)
        XCTAssertTrue(try gesture(.began, at: inside))
        let cardBeforeExit = clip.bounds.origin
        XCTAssertFalse(try gesture(.changed, at: outside))
        XCTAssertEqual(clip.bounds.origin, cardBeforeExit)
        let outsideWheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                                wheelCount: 1, wheel1: -4, wheel2: 0, wheel3: 0))
        outer.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: outsideWheel)))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotEqual(outer.contentView.bounds.origin, outerStart)
        XCTAssertFalse(try gesture(.ended, at: outside))

        // A new gesture started outside can also move into the card.
        XCTAssertFalse(try gesture(.began, at: outside))
        let pageBeforeEntry = outer.contentView.bounds.origin
        let visiblePoint = NSPoint(x: card.visibleRect.midX, y: card.visibleRect.midY)
        XCTAssertTrue(try gesture(.changed, at: visiblePoint))
        XCTAssertEqual(outer.contentView.bounds.origin, pageBeforeEntry)
        XCTAssertTrue(try gesture(.ended, at: visiblePoint))
        XCTAssertFalse(card.scroller.hasVerticalScroller)
    }
}
