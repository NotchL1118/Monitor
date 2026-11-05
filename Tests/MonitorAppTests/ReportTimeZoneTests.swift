import XCTest
import MonitorCore
@testable import Monitor

final class ReportTimeZoneTests: XCTestCase {
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    private var beijing: Calendar { ReportTimeZone.utcPlus8.calendar }
    private var pacific: Calendar {
        var calendar = ReportPeriod.calendar
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testFixedUTC8FormattingAndCalendarBoundaries() {
        let instant = date("2026-11-04T16:30:00Z")
        XCTAssertEqual(ReportTimeZone.utcPlus8.timeZone.secondsFromGMT(for: instant), 28800)
        XCTAssertEqual(ReportTimeZone.utcPlus8.timeZone.secondsFromGMT(for: date("2026-06-04T16:30:00Z")), 28800)
        XCTAssertEqual(ReportPeriod.day.label(for: instant, calendar: beijing), "2026年11月5日")
        XCTAssertEqual(ReportPeriod.day.label(for: instant, calendar: pacific), "2026年11月4日")
        XCTAssertEqual(instant.formatted(ReportTimeZone.utcPlus8.formatStyle.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)), "00:30")
        XCTAssertEqual(ReportPeriod.day.interval(containing: instant, calendar: beijing).start, date("2026-11-04T16:00:00Z"))
        XCTAssertEqual(ReportPeriod.week.interval(containing: instant, calendar: beijing).start, date("2026-11-01T16:00:00Z"))
        XCTAssertEqual(ReportPeriod.month.interval(containing: date("2026-12-31T16:30:00Z"), calendar: beijing).start,
                       date("2026-12-31T16:00:00Z"))
    }

    func testTodayAndApplicationDetailAgreeAfterTimeZoneChange() throws {
        let store = try ActivityStore(path: ":memory:")
        let start = date("2026-11-04T15:50:00Z"), end = date("2026-11-04T16:20:00Z")
        let now = date("2026-11-04T16:30:00Z")
        try store.record([ActivitySlice(kind: .application, key: "editor", name: "Editor", start: start, end: end)])
        let bjToday = try TodaySnapshot.read(from: store, at: now, calendar: beijing)
        let laToday = try TodaySnapshot.read(from: store, at: now, calendar: pacific)
        XCTAssertEqual(bjToday.total, 1200)
        XCTAssertEqual(laToday.total, 1800)
        XCTAssertEqual(bjToday.bars.reduce(0, +), laToday.bars.reduce(0, +))
        XCTAssertEqual(bjToday.bars.reduce(0, +), 1800)
        let interval = ReportPeriod.day.interval(containing: now, calendar: beijing)
        let rows = try store.sessions(kind: .application, key: "editor", from: interval.start, to: interval.end)
        let report = ApplicationReport(application: ActivityIdentity(key: "editor", name: "Editor"),
            period: .day, interval: interval, sessions: rows, now: now, calendar: beijing)
        XCTAssertEqual(report.seconds, bjToday.total)
        XCTAssertEqual(report.buckets.first?.seconds, 1200)
        XCTAssertEqual(report.days.first?.date, interval.start)
        XCTAssertEqual(report.calendar.timeZone, beijing.timeZone)
        let original = try XCTUnwrap(store.activities(from: .distantPast, to: .distantFuture).first)
        XCTAssertEqual(original.start, start)
        XCTAssertEqual(original.end, end)
    }

    @MainActor
    func testPreferencePersistsAndHistoricalCalendarDayIsPreserved() throws {
        let name = "Monitor-TimeZone-QA-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let model = MonitorModel(preferences: preferences)
        XCTAssertEqual(model.reportTimeZone, .system)
        let oldCalendar = model.reportCalendar
        model.selectedDate = oldCalendar.date(from: DateComponents(year: 2023, month: 1, day: 5))!
        model.reportTimeZone = .utcPlus8
        XCTAssertEqual(model.reportLabel, "2023年1月5日")
        XCTAssertEqual(model.reportInterval.start, date("2023-01-04T16:00:00Z"))
        model.stepPeriod(-1)
        XCTAssertEqual(model.reportLabel, "2023年1月4日")
        let restored = MonitorModel(preferences: preferences)
        XCTAssertEqual(restored.reportTimeZone, .utcPlus8)
        model.selectedDate = Date()
        model.reportTimeZone = .system
        XCTAssertEqual(model.reportInterval.start, model.reportCalendar.startOfDay(for: Date()))
        preferences.set("invalid-zone", forKey: ReportTimeZone.preferenceKey)
        XCTAssertEqual(MonitorModel(preferences: preferences).reportTimeZone, .system)
    }
}
