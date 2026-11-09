import Foundation
import MonitorCore

enum BrowserLevel: String, CaseIterable { case site = "网站", page = "页面" }

enum BrowserMetric: String, CaseIterable {
    case duration = "停留时长", visits = "访问次数"

    func value(_ group: BrowserGroup) -> Double {
        self == .duration ? group.seconds : Double(group.visits.count)
    }

    func label(_ group: BrowserGroup) -> String {
        self == .duration ? durationText(group.seconds) : "\(group.visits.count) 次"
    }

    func ranked(_ groups: [BrowserGroup]) -> [BrowserGroup] {
        groups.sorted { a, b in
            if value(a) != value(b) { return value(a) > value(b) }
            if a.seconds != b.seconds { return a.seconds > b.seconds }
            return a.id < b.id
        }
    }
}

struct BrowserGroup: Identifiable {
    let id: String
    let title: String
    let visits: [ActivitySlice]
    let seconds: Double

    init(id: String, title: String, visits: [ActivitySlice]) {
        self.id = id
        self.title = title
        self.visits = visits
        seconds = visits.reduce(0) { $0 + $1.seconds }
    }
}

struct BrowserBucket: Identifiable {
    let interval: DateInterval
    let sites: [UsageSummary]
    var id: Date { interval.start }
    var seconds: Double { sites.reduce(0) { $0 + $1.seconds } }
}

struct BrowserReport {
    let chrome: ApplicationReport
    let visits: [ActivitySlice]
    let sites: [BrowserGroup]
    let hosts: [BrowserGroup]
    let pages: [BrowserGroup]
    let buckets: [BrowserBucket]
    let seconds: Double
    let unaddressedSeconds: Double
    /// Registrable site for every host in this report.
    let siteKeys: [String: String]
    /// Web time in the comparison span, by site. Empty when that span has no web records.
    let previousSites: [String: Double]
    let previousSeconds: Double
    let comparisonLabel: String

    var hasComparison: Bool { previousSeconds > 0 }
    var averageVisitSeconds: Double { visits.isEmpty ? 0 : seconds / Double(visits.count) }
    var longestVisit: ActivitySlice? { visits.max { $0.seconds != $1.seconds ? $0.seconds < $1.seconds : $0.start > $1.start } }
    /// Share of Chrome foreground time that has a web record, when Chrome time is known.
    var chromeCoverage: Double? { chrome.seconds > 0 ? min(1, seconds / chrome.seconds) : nil }

    /// `previousInterval` is the comparison span (the previous period, cut at the same elapsed time
    /// when the current period is still running); `previousWebsites` are its raw website slices.
    init(period: ReportPeriod, interval: DateInterval, calendar: Calendar, websites: [ActivitySlice],
         sessions: [ActivitySlice], previousWebsites: [ActivitySlice] = [], previousInterval: DateInterval? = nil,
         now: Date = Date()) {
        chrome = ApplicationReport(application: ActivityIdentity(key: ActivityTracker.chromeBundleID, name: "Google Chrome"),
            period: period, interval: interval, sessions: sessions, now: now, calendar: calendar)
        let elapsed = DateInterval(start: interval.start, end: max(interval.start, min(now, interval.end)))
        let visits = websites.filter { $0.kind == .website }.compactMap { Self.clip($0, to: elapsed) }.sorted { $0.start < $1.start }
        self.visits = visits
        seconds = visits.reduce(0) { $0 + $1.seconds }
        unaddressedSeconds = visits.filter { $0.pageURL == nil }.reduce(0) { $0 + $1.seconds }
        let byHost = Dictionary(grouping: visits, by: \.key)
        hosts = byHost.map { BrowserGroup(id: $0.key, title: $0.key, visits: $0.value) }
        let siteKeys = byHost.mapValues { SiteDomain.shared.site(for: $0[0].key) }
        self.siteKeys = siteKeys
        sites = Self.siteGroups(in: visits, siteKeys: siteKeys)
        pages = Self.pageGroups(in: visits)
        buckets = chrome.buckets.map { bucket in
            var totals: [String: Double] = [:]
            for visit in visits.overlapping(bucket.interval) {
                let start = max(visit.start, bucket.interval.start), end = min(visit.end, bucket.interval.end)
                totals[siteKeys[visit.key]!, default: 0] += end.timeIntervalSince(start)
            }
            let sites = totals.map { UsageSummary(key: $0.key, name: Self.siteTitle($0.key), seconds: $0.value) }
                .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.key < $1.key }
            return BrowserBucket(interval: bucket.interval, sites: sites)
        }
        var previous: [String: Double] = [:]
        if let previousInterval {
            for slice in previousWebsites where slice.kind == .website {
                guard let clipped = Self.clip(slice, to: previousInterval) else { continue }
                previous[SiteDomain.shared.site(for: clipped.key), default: 0] += clipped.seconds
            }
        }
        previousSites = previous
        previousSeconds = previous.values.reduce(0, +)
        let running = now < interval.end
        switch period {
        case .day: comparisonLabel = running ? "比昨天同期" : "比前一天"
        case .week: comparisonLabel = running ? "比上周同期" : "比上一周"
        case .month: comparisonLabel = running ? "比上月同期" : "比上个月"
        }
    }

    /// Rankings for a level, optionally restricted to one chart bucket. Visits are clipped to the span.
    func groups(at level: BrowserLevel, within span: DateInterval? = nil) -> [BrowserGroup] {
        guard let span else {
            switch level {
            case .site: return sites
            case .page: return pages
            }
        }
        let clipped = visits.overlapping(span).compactMap { Self.clip($0, to: span) }
        return level == .site ? Self.siteGroups(in: clipped, siteKeys: siteKeys) : Self.pageGroups(in: clipped)
    }

    func hosts(inSite site: String) -> [BrowserGroup] {
        hosts.filter { siteKeys[$0.id] == site }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.id < $1.id }
    }

    func site(of visit: ActivitySlice) -> String { siteKeys[visit.key] ?? SiteDomain.shared.site(for: visit.key) }

    static func siteGroups(in visits: [ActivitySlice], siteKeys: [String: String]) -> [BrowserGroup] {
        Dictionary(grouping: visits) { siteKeys[$0.key] ?? SiteDomain.shared.site(for: $0.key) }
            .map { BrowserGroup(id: $0.key, title: siteTitle($0.key), visits: $0.value) }
    }

    static func pageGroups(in visits: [ActivitySlice], includingUnaddressed: Bool = false) -> [BrowserGroup] {
        // A bare host cannot collide with an HTTP(S) page URL. Domain-only history
        // has its own detail row, without contributing an invented page to the ranking.
        let rows = includingUnaddressed ? visits : visits.filter { $0.pageURL != nil }
        return Dictionary(grouping: rows, by: { $0.pageURL ?? $0.key }).map { key, group in
            let title: String
            if group[0].pageURL == nil { title = "仅域名记录 · \(key)" }
            else { title = (group.reversed().compactMap(\.pageTitle).first { !$0.isEmpty }).map(PageTitle.display) ?? key }
            return BrowserGroup(id: key, title: title, visits: group)
        }
    }

    func visits(in session: ActivitySlice) -> [ActivitySlice] {
        let span = DateInterval(start: session.start, end: session.end)
        return visits.overlapping(span).compactMap { Self.clip($0, to: span) }
    }

    static func clip(_ visit: ActivitySlice, to span: DateInterval) -> ActivitySlice? {
        let start = max(visit.start, span.start), end = min(visit.end, span.end)
        guard start < end else { return nil }
        return ActivitySlice(id: visit.id, kind: visit.kind, key: visit.key, name: visit.name,
            start: start, end: end, pageURL: visit.pageURL, pageTitle: visit.pageTitle)
    }

    static func siteTitle(_ domain: String) -> String {
        switch domain {
        case "google.com": return "Google"
        case "github.com": return "GitHub"
        case "youtube.com": return "YouTube"
        case "figma.com": return "Figma"
        case "apple.com": return "Apple"
        case "bilibili.com": return "哔哩哔哩"
        case "juejin.cn": return "稀土掘金"
        case "zhihu.com": return "知乎"
        case "stackoverflow.com": return "Stack Overflow"
        default: return domain
        }
    }
}
