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

    func testReportClipsToDayAndElapsedTimeAndKeepsRawTotals() {
        let report = DayTimelineReport(date: day, calendar: calendar,
            activities: [app(1, -10, 30), app(2, 60, 150), app(3, 200, 300)], now: day.addingTimeInterval(120))
        XCTAssertEqual(report.seconds, 90)
        XCTAssertEqual(report.firstActivity, day)
        XCTAssertEqual(report.lastActivity, day.addingTimeInterval(120))
        XCTAssertEqual(report.range, DateInterval(start: day, duration: 3600))
        XCTAssertEqual(report.segments.count, 1)
        XCTAssertEqual(report.segments[0].activeSeconds, 90)
    }

    func testOverviewLanesKeepEveryUseAndFoldTheRestIntoOther() {
        let keys = ["a", "b", "c", "d", "e", "f", "g"]
        let sessions: [ActivitySlice] = (0..<70).map { index in
            let start = 32400.0 + Double(index) * 60
            return app(Int64(index + 1), start, start + 50, key: keys[index % keys.count])
        }
        let report = DayTimelineReport(date: day, calendar: calendar, activities: sessions, now: day.addingTimeInterval(86400))
        XCTAssertEqual(report.lanes.count, DayTimelineReport.laneCount + 1)
        XCTAssertNil(report.lanes.last?.key)
        XCTAssertEqual(report.lanes.flatMap(\.runs).count, 70)
        XCTAssertEqual(report.lanes.reduce(0) { $0 + $1.seconds }, report.seconds)
        XCTAssertEqual(report.seconds, 3500)
        XCTAssertEqual(Set(report.colors.values).count, report.colors.count)
        XCTAssertEqual(report.switches, 69)
        XCTAssertEqual(report.range.start, day.addingTimeInterval(9 * 3600))
        XCTAssertEqual(report.range.end, day.addingTimeInterval(11 * 3600))
    }

    func testAbsenceAndPeriodTitles() {
        let report = DayTimelineReport(date: day, calendar: calendar, activities: [
            app(1, 0, 1800, key: "chat"), app(2, 1800, 1900, key: "wechat"), app(3, 1900, 3600, key: "chat"),
            app(4, 7200, 9000, key: "editor")
        ], now: day.addingTimeInterval(86400))
        XCTAssertEqual(report.segments.map(\.apps.first?.key), ["chat", "editor"])
        XCTAssertEqual(report.awayCount, 1)
        XCTAssertEqual(report.segments.map(DayTimelineReport.title), ["chat", "editor"])
        XCTAssertEqual(report.block(at: day.addingTimeInterval(5000))?.segment == nil, true)
        XCTAssertEqual(report.application(at: day.addingTimeInterval(1850))?.key, "wechat")
        XCTAssertEqual(report.seconds, 5400)
    }

    func testDSTDayAndEmptyDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let report = DayTimelineReport(date: day, calendar: calendar, activities: [], now: day.addingTimeInterval(100000))
        XCTAssertEqual(report.interval.duration, 25 * 3600)
        XCTAssertTrue(report.blocks.isEmpty)
        XCTAssertTrue(report.lanes.isEmpty)
    }

    func testBriefSwitchesStillMergeInApplicationDetail() {
        let detail = ApplicationReport(application: ActivityIdentity(key: "chat", name: "chat"), period: .day,
            interval: DateInterval(start: day, duration: 86400),
            sessions: [app(1, 0, 600, key: "chat"), app(3, 601, 900, key: "chat")], now: day.addingTimeInterval(86400), calendar: calendar)
        XCTAssertEqual(detail.sessions.count, 1)
        XCTAssertEqual(detail.seconds, 899)
        XCTAssertEqual(detail.longest, 900)
        XCTAssertEqual(detail.days.first?.seconds, 899)
        XCTAssertEqual(detail.buckets.reduce(0) { $0 + $1.seconds }, 899)
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
