import Foundation
import MonitorCore

/// The status item always reports today, even while the main window is browsing history.
struct TodaySnapshot {
    static let bucketWidth: TimeInterval = 600
    let date: Date
    let apps: [UsageSummary]
    let sites: [UsageSummary]
    let bars: [Double]

    var total: Double { apps.reduce(0) { $0 + $1.seconds } }
    var browsing: Double { sites.reduce(0) { $0 + $1.seconds } }
    var chartStart: Date { date.addingTimeInterval(-Double(bars.count) * Self.bucketWidth) }

    static func empty(at date: Date) -> Self {
        Self(date: date, apps: [], sites: [], bars: Array(repeating: 0, count: 18))
    }

    static func read(from store: ActivityStore, at now: Date, calendar: Calendar = ReportPeriod.calendar) throws -> Self {
        let day = calendar.startOfDay(for: now)
        let apps = try store.summaries(kind: .application, from: day, to: now)
        let sites = try store.summaries(kind: .website, from: day, to: now)
        var bins = Array(repeating: 0.0, count: 18)
        let start = now.addingTimeInterval(-Double(bins.count) * bucketWidth)
        let activities = try store.activities(from: start, to: now, limit: -1)
        for row in activities where row.kind == .application {
            let offset = row.start.timeIntervalSince(start)
            let end = row.end.timeIntervalSince(start)
            let first = max(0, Int(floor(offset / bucketWidth)))
            let afterLast = min(bins.count, Int(ceil(end / bucketWidth)))
            guard first < afterLast else { continue }
            for i in first..<afterLast {
                let left = Double(i) * bucketWidth
                bins[i] += min(end, left + bucketWidth) - max(offset, left)
            }
        }
        return Self(date: now, apps: apps, sites: sites, bars: bins)
    }
}
