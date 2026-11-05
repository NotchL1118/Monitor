import XCTest
import AppKit
import SwiftUI
import MonitorCore
@testable import Monitor

final class ApplicationReportTests: XCTestCase {
    private var calendar: Calendar {
        var c = ReportPeriod.calendar
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private let identity = ActivityIdentity(key: "com.openai.chat", name: "ChatGPT")
    private func session(_ id: Int64, _ start: Date, _ end: Date) -> ActivitySlice {
        ActivitySlice(id: id, kind: .application, key: identity.key, name: identity.name, start: start, end: end)
    }

    func testMidnightSplitAndDailyTotalsConserveDuration() {
        let sessions = [session(1, date(3, 23, 50), date(4, 0, 20)), session(2, date(4, 9), date(4, 10))]
        let span = ReportPeriod.week.interval(containing: date(4), calendar: calendar)
        let report = ApplicationReport(application: identity, period: .week, interval: span,
                                       sessions: sessions, now: date(9), calendar: calendar)
        XCTAssertEqual(report.sessions.count, 2)
        XCTAssertEqual(report.days.count, 2)
        XCTAssertEqual(report.days[0].seconds, 600)
        XCTAssertEqual(report.days[1].seconds, 4800)
        XCTAssertEqual(report.seconds, 5400)
        XCTAssertEqual(report.buckets.reduce(0) { $0 + $1.seconds }, report.seconds)
        XCTAssertEqual(report.longest, 3600)
        XCTAssertEqual(report.days[1].sessions.first?.start, date(4))
    }

    func testFallBackDayHas25HoursAndRangeAndNowClipping() {
        let span = ReportPeriod.day.interval(containing: date(1), calendar: calendar)
        let slices = [session(1, date(1).addingTimeInterval(-100), date(2).addingTimeInterval(100))]
        let full = ApplicationReport(application: identity, period: .day, interval: span,
                                     sessions: slices, now: date(3), calendar: calendar)
        XCTAssertEqual(full.buckets.count, 25)
        XCTAssertEqual(Set(full.buckets.map(\.id)).count, 25)
        XCTAssertEqual(full.seconds, 25 * 3600)
        XCTAssertEqual(full.buckets.reduce(0) { $0 + $1.seconds }, full.seconds)
        let now = date(1, 10, 15)
        let partial = ApplicationReport(application: identity, period: .day, interval: span,
                                        sessions: slices, now: now, calendar: calendar)
        XCTAssertEqual(partial.sessions.last?.end, now)
        XCTAssertTrue(partial.buckets.allSatisfy { $0.interval.start < now })
        XCTAssertEqual(partial.buckets.last?.seconds, 15 * 60)
        XCTAssertNil(partial.bucket(containing: span.end))
        XCTAssertEqual(partial.buckets.reduce(0) { $0 + $1.seconds }, partial.seconds)
    }

    func testMonthEmptyDaysAndSessionsOutsideRange() {
        let span = ReportPeriod.month.interval(containing: date(4), calendar: calendar)
        let report = ApplicationReport(application: identity, period: .month, interval: span,
            sessions: [session(1, date(3, 9), date(3, 10)), session(2, date(7, 9), date(7, 10))],
            now: date(5), calendar: calendar)
        XCTAssertEqual(report.buckets.count, 4)
        XCTAssertEqual(report.buckets.map(\.seconds), [0, 0, 3600, 0])
        XCTAssertEqual(report.seconds, 3600)
        XCTAssertEqual(report.sessions.count, 1)
        XCTAssertNil(report.bucket(containing: date(6)))
    }

    @MainActor
    func testDetailRenderingAtBothWindowWidths() async throws {
        _ = NSApplication.shared
        let sessions = [session(1, date(4, 9, 12), date(4, 9, 30)),
                        session(2, date(4, 10, 8), date(4, 10, 40)),
                        session(3, date(4, 11, 20), date(4, 11, 45)),
                        session(4, date(4, 14, 5), date(4, 14, 25)),
                        session(5, date(4, 15, 32), date(4, 16, 10)),
                        session(6, date(4, 20, 18), date(4, 20, 45))]
        let model = MonitorModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 1000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = project.appendingPathComponent(".build/qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for period in ReportPeriod.allCases {
            let span = period.interval(containing: date(4), calendar: calendar)
            let history = period == .day ? sessions : (0..<10).flatMap { offset in
                sessions.prefix(2 + offset % 5).map { s in
                    session(s.id + Int64(offset * 10), calendar.date(byAdding: .day, value: -offset, to: s.start)!,
                            calendar.date(byAdding: .day, value: -offset, to: s.end)!)
                }
            }
            let report = ApplicationReport(application: identity, period: period, interval: span,
                                           sessions: history, now: date(5), calendar: calendar)
            for width in [620, 820] {
                let root = ScrollView {
                    ApplicationDetailView(report: report).environmentObject(model).padding(20)
                }.scrollIndicators(.hidden).background(Palette.background).preferredColorScheme(.light)
                let host = NSHostingView(rootView: root)
                window.setContentSize(NSSize(width: width, height: 1000))
                window.contentView = host
                window.orderFront(nil)
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 10000)
                try png.write(to: output.appendingPathComponent("application-\(period)-\(width).png"))
            }
        }
    }
}
