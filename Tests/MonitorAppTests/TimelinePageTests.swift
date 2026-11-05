import XCTest
import MonitorCore
@testable import Monitor

final class TimelinePageTests: XCTestCase {
    private let calendar = ReportTimeZone.utcPlus8.calendar
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))! }
    private func app(_ id: Int64, _ a: Double, _ b: Double, key: String = "editor") -> ActivitySlice {
        ActivitySlice(id: id, kind: .application, key: key, name: key,
                      start: day.addingTimeInterval(a), end: day.addingTimeInterval(b))
    }

    func testContinuousTimelineClipsMidnightIncludesGapsAndNeverCallsFutureUnrecorded() {
        let report = DayTimelineReport(date: day, calendar: calendar,
            sessions: [app(1, -10, 30), app(2, 60, 150), app(3, 200, 300)], now: day.addingTimeInterval(120))
        XCTAssertEqual(report.sessions.count, 2)
        XCTAssertEqual(report.seconds, 90)
        XCTAssertEqual(report.lanes.count, 1)
        XCTAssertEqual(report.lanes[0].segments.map(\.seconds), [30, 30, 60])
        XCTAssertNil(report.lanes[0].segments[1].activity)
        XCTAssertEqual(report.lanes.last?.segments.last?.end, day.addingTimeInterval(120))
        XCTAssertEqual(report.lanes.last?.interval.end, day.addingTimeInterval(4 * 3600))
    }

    func testDenseTimelineRetainsAllSessionsAndZoomDoesNotChangeTotals() {
        let sessions: [ActivitySlice] = (0..<260).map { index in
            let start = 32400.0 + Double(index) * 20
            return app(Int64(index + 1), start, start + 10)
        }
        for hours in [2, 4] {
            let report = DayTimelineReport(date: day, calendar: calendar, sessions: sessions,
                hoursPerLane: hours, now: day.addingTimeInterval(86400))
            XCTAssertEqual(report.sessions.count, 260)
            XCTAssertEqual(report.seconds, 2600)
            let spans = report.lanes.flatMap(\.segments)
            XCTAssertEqual(spans.reduce(0) { $0 + $1.seconds }, 86400)
            XCTAssertEqual(spans.filter { $0.activity != nil }.reduce(0) { $0 + $1.seconds }, 2600)
        }
    }

    func testDSTDayAndNoRecordLanesAreCollapsed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let report = DayTimelineReport(date: day, calendar: calendar, sessions: [], now: day.addingTimeInterval(100000))
        XCTAssertEqual(report.interval.duration, 25 * 3600)
        XCTAssertEqual(report.lanes.count, 1)
        XCTAssertEqual(report.lanes.first?.interval.duration, 25 * 3600)
    }

    func testBrowserDetailsClipToApplicationSessionAndKeepDomainOnlyHistory() {
        let chrome = ActivityIdentity(key: ActivityTracker.chromeBundleID, name: "Chrome")
        let session = app(1, 60, 180, key: chrome.key)
        let pages = [
            ActivitySlice(id: 2, kind: .website, key: "example.com", name: "example.com", start: day, end: day.addingTimeInterval(90)),
            ActivitySlice(id: 3, kind: .website, key: "example.com", name: "example.com", start: day.addingTimeInterval(90), end: day.addingTimeInterval(200),
                          pageURL: "https://example.com/a", pageTitle: "Page A")
        ]
        let report = ApplicationReport(application: chrome, period: .day, interval: DateInterval(start: day, duration: 86400),
            sessions: [session], now: day.addingTimeInterval(86400), calendar: calendar, websites: pages)
        let visits = report.browserVisits(in: session)
        XCTAssertEqual(visits.map(\.seconds), [30, 90])
        XCTAssertNil(visits[0].pageURL)
        XCTAssertEqual(visits[1].pageTitle, "Page A")
        XCTAssertEqual(BrowserVisitGroup.groups(visits).count, 1)
        XCTAssertEqual(visits.reduce(0) { $0 + $1.seconds }, report.seconds)
    }
}
