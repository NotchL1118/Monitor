import XCTest
import MonitorCore
@testable import Monitor

final class BrowserReportTests: XCTestCase {
    func testWebsiteBoundariesIncludePrivateSuffixesExceptionsAndIPs() {
        let examples = [
            "docs.google.com": "google.com", "a.news.example.co.uk": "example.co.uk",
            "docs.alice.github.io": "alice.github.io", "bob.github.io": "bob.github.io",
            "www.city.kawasaki.jp": "city.kawasaki.jp", "a.b.foo.kawasaki.jp": "b.foo.kawasaki.jp",
            "a.example.xn--55qx5d.cn": "example.xn--55qx5d.cn",
            "10.0.0.1": "10.0.0.1", "localhost": "localhost"
        ]
        for (host, expected) in examples { XCTAssertEqual(SiteDomain.shared.site(for: host), expected, host) }
    }

    func testRankingsUseClippedVisitsAndDoNotInventPagesForOldRecords() throws {
        let calendar = ReportTimeZone.utcPlus8.calendar
        let span = ReportPeriod.day.interval(containing: Date(), calendar: calendar)
        func visit(_ id: Int64, _ key: String, _ start: Double, _ end: Double, _ path: String? = nil, _ title: String? = nil) -> ActivitySlice {
            ActivitySlice(id: id, kind: .website, key: key, name: key,
                start: span.start.addingTimeInterval(start), end: span.start.addingTimeInterval(end),
                pageURL: path.map { "https://" + key + $0 }, pageTitle: title)
        }
        let rows = [
            visit(1,"docs.example.com",-20,40,"/a","旧标题"),
            visit(2,"mail.example.com",40,50,"/inbox","收件箱"),
            visit(3,"other.org",3590,3630,"/one","同一标题"),
            visit(4,"mail.example.com",3630,3640,"/inbox","收件箱"),
            visit(5,"docs.example.com",3640,3670,"/a","新标题"),
            visit(6,"legacy.example.com",3670,3700),
            visit(7,"other.org",3700,4000,"/two","同一标题")
        ]
        let report = BrowserReport(period: .day, interval: span, calendar: calendar, websites: rows.reversed(),
                                   sessions: [], now: span.start.addingTimeInterval(3710))
        XCTAssertEqual(report.visits.count, 7)
        XCTAssertEqual(report.seconds, 170)
        XCTAssertEqual(report.pages.count, 4)
        XCTAssertEqual(report.unaddressedSeconds, 30)
        XCTAssertEqual(report.sites.map(\.seconds).reduce(0,+), report.seconds)
        let top = try XCTUnwrap(BrowserMetric.duration.ranked(report.sites).first)
        XCTAssertEqual(top.id, "example.com")
        XCTAssertEqual(top.visits.count, 5)
        let pages = BrowserReport.pageGroups(in: top.visits, includingUnaddressed: true)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(BrowserMetric.duration.ranked(pages).first?.title, "新标题")
        XCTAssertEqual(pages.map(\.seconds).reduce(0,+), top.seconds)
        XCTAssertEqual(report.buckets.map(\.seconds), [60,110])
        XCTAssertEqual(report.buckets[0].sites.first?.key, "example.com")
        XCTAssertEqual(report.buckets[1].sites.first?.key, "example.com")
    }

    func testChangingMetricChangesLeadersAndDayBucketsRespectClockRollback() throws {
        var calendar = ReportPeriod.calendar
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let span = ReportPeriod.day.interval(containing: day, calendar: calendar)
        let samples: [(String, Double, Double)] = [("deep.org",3600,7200),("quick.net",7200,7210),("quick.net",7220,7230)]
        let rows = samples.enumerated().map { index, record in
            ActivitySlice(id: Int64(index), kind: .website, key: record.0, name: record.0,
                          start: day.addingTimeInterval(record.1), end: day.addingTimeInterval(record.2))
        }
        let report = BrowserReport(period: .day, interval: span, calendar: calendar, websites: rows, sessions: [], now: span.end)
        XCTAssertEqual(report.buckets.count, 25)
        XCTAssertEqual(report.buckets.map(\.seconds).reduce(0,+), 3620)
        XCTAssertEqual(BrowserMetric.duration.ranked(report.sites).first?.id, "deep.org")
        XCTAssertEqual(BrowserMetric.visits.ranked(report.sites).first?.id, "quick.net")
        XCTAssertTrue(report.pages.isEmpty)
    }

    func testTitlesHideEmailAddressesAndMaskCodesOnlyWhenTheTitleMentionsACode() {
        XCTAssertEqual(PageTitle.display("收件箱 (74) - someone.name@gmail.com - Gmail"), "收件箱 (74) - Gmail")
        XCTAssertEqual(PageTitle.display("someone@example.com"), "（邮箱地址已隐藏）")
        XCTAssertEqual(PageTitle.display("用验证码 950483 登录 - a@b.cn - Gmail"), "用验证码 •••••• 登录 - Gmail")
        XCTAssertEqual(PageTitle.display("G-482913 is your Google verification code"), "G-•••••• is your Google verification code")
        XCTAssertEqual(PageTitle.display("Pull request #1234 · 2026 年计划"), "Pull request #1234 · 2026 年计划")
        XCTAssertEqual(PageTitle.display("收件箱 (74)"), "收件箱 (74)")
    }

    func testComparisonBucketFilterAndVisitStatistics() throws {
        let calendar = ReportTimeZone.utcPlus8.calendar
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        let span = ReportPeriod.day.interval(containing: day, calendar: calendar)
        func visit(_ id: Int64, _ key: String, _ start: Double, _ end: Double, base: Date) -> ActivitySlice {
            ActivitySlice(id: id, kind: .website, key: key, name: key, start: base.addingTimeInterval(start),
                          end: base.addingTimeInterval(end), pageURL: "https://\(key)/\(id)", pageTitle: "页面 \(id)")
        }
        let rows = [
            visit(1, "mail.google.com", 3000, 4200, base: day),   // 00:50–01:10, crosses an hour
            visit(2, "www.google.com", 4200, 4260, base: day),
            visit(3, "juejin.cn", 7200, 7500, base: day)
        ]
        let yesterday = day.addingTimeInterval(-86400)
        let previous = [visit(9, "mail.google.com", 0, 600, base: yesterday), visit(10, "juejin.cn", 7000, 8000, base: yesterday)]
        // The day is still running at 02:30, so yesterday is cut at 02:30 as well.
        let now = day.addingTimeInterval(9000)
        let report = BrowserReport(period: .day, interval: span, calendar: calendar, websites: rows, sessions: [],
            previousWebsites: previous, previousInterval: DateInterval(start: yesterday, duration: 9000), now: now)
        XCTAssertEqual(report.comparisonLabel, "比昨天同期")
        XCTAssertEqual(report.previousSeconds, 1600)
        XCTAssertEqual(report.previousSites["google.com"], 600)
        XCTAssertEqual(report.averageVisitSeconds, 520)
        XCTAssertEqual(report.longestVisit?.id, 1)
        XCTAssertEqual(report.hosts(inSite: "google.com").map(\.id), ["mail.google.com", "www.google.com"])

        let firstHour = try XCTUnwrap(report.buckets.first?.interval)
        let early = report.groups(at: .site, within: firstHour)
        XCTAssertEqual(early.map(\.id), ["google.com"])
        XCTAssertEqual(early.first?.seconds, 600)
        let secondHour = report.buckets[1].interval
        XCTAssertEqual(report.groups(at: .site, within: secondHour).first?.seconds, 660)
        XCTAssertEqual(report.groups(at: .page, within: secondHour).count, 2)
        XCTAssertEqual(report.groups(at: .site).map(\.seconds).reduce(0, +), report.seconds)

        let finished = BrowserReport(period: .day, interval: span, calendar: calendar, websites: rows, sessions: [], now: span.end)
        XCTAssertEqual(finished.comparisonLabel, "比前一天")
        XCTAssertFalse(finished.hasComparison)
    }

    func testFilteredTimelineHasNoGapRows() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ActivitySlice(id: 1, kind: .application, key: ActivityTracker.chromeBundleID, name: "Chrome",
                                    start: start, end: start.addingTimeInterval(300))
        let visits = [ActivitySlice(id: 2, kind: .website, key: "a.test", name: "a.test",
                                    start: start.addingTimeInterval(100), end: start.addingTimeInterval(160))]
        XCTAssertEqual(BrowserVisitTimeline(session: session, visits: visits, activeSeconds: 300).rows.count, 3)
        let filtered = BrowserVisitTimeline(session: session, visits: visits, activeSeconds: 300, showsGaps: false)
        XCTAssertEqual(filtered.rows.count, 1)
        XCTAssertEqual(filtered.missingSeconds, 0)
    }
}
