import Foundation
import MonitorCore

struct UsageBucket: Identifiable {
    let interval: DateInterval
    let seconds: Double
    var id: Date { interval.start }
    var midpoint: Date { interval.start.addingTimeInterval(interval.duration / 2) }
}

struct SessionDay: Identifiable {
    let date: Date
    let sessions: [ActivitySlice]
    var id: Date { date }
    var seconds: Double { sessions.reduce(0) { $0 + $1.seconds } }
}

struct ApplicationReport {
    let application: ActivityIdentity
    let period: ReportPeriod
    let interval: DateInterval
    let calendar: Calendar
    let sessions: [ActivitySlice]
    let buckets: [UsageBucket]
    let days: [SessionDay]
    let websites: [ActivitySlice]
    var seconds: Double { sessions.reduce(0) { $0 + $1.seconds } }
    var longest: Double { sessions.map(\.seconds).max() ?? 0 }
    var peak: UsageBucket? { buckets.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds } }

    init(application: ActivityIdentity, period: ReportPeriod, interval: DateInterval,
         sessions: [ActivitySlice], now: Date = Date(), calendar: Calendar = ReportPeriod.calendar, websites: [ActivitySlice] = []) {
        self.application = application
        self.period = period
        self.interval = interval
        self.calendar = calendar
        self.websites = websites.filter { $0.kind == .website }.sorted { $0.start < $1.start }
        let end = min(interval.end, now)
        let clipped = sessions.compactMap { slice -> ActivitySlice? in
            guard slice.kind == .application, slice.key == application.key else { return nil }
            let start = max(slice.start, interval.start), stop = min(slice.end, end)
            guard start < stop else { return nil }
            return ActivitySlice(id: slice.id, kind: slice.kind, key: slice.key, name: slice.name, start: start, end: stop)
        }.sorted { $0.start < $1.start }
        self.sessions = clipped
        var grouped: [Date: [ActivitySlice]] = [:]
        for slice in clipped {
            var cursor = slice.start
            while cursor < slice.end {
                let day = calendar.dateInterval(of: .day, for: cursor)!
                let stop = min(slice.end, day.end)
                grouped[day.start, default: []].append(ActivitySlice(id: slice.id, kind: slice.kind,
                    key: slice.key, name: slice.name, start: cursor, end: stop))
                cursor = stop
            }
        }
        days = grouped.keys.sorted().map { SessionDay(date: $0, sessions: grouped[$0]!) }

        // Calendar arithmetic preserves 23/25-hour days. Future buckets are absent, not zero.
        var result: [UsageBucket] = []
        var cursor = interval.start
        let unit: Calendar.Component = period == .day ? .hour : .day
        while cursor < end {
            let next = min(calendar.date(byAdding: unit, value: 1, to: cursor)!, interval.end)
            let seconds = clipped.reduce(0.0) { total, slice in
                total + max(0, min(slice.end, next).timeIntervalSince(max(slice.start, cursor)))
            }
            result.append(UsageBucket(interval: DateInterval(start: cursor, end: next), seconds: seconds))
            cursor = next
        }
        buckets = result
    }

    func browserVisits(in session: ActivitySlice) -> [ActivitySlice] {
        guard application.key == ActivityTracker.chromeBundleID else { return [] }
        // Website visits are non-overlapping and chronological. Seek directly to this
        // application's session so month reports don't repeatedly scan the full history.
        var lower = 0, upper = websites.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if websites[mid].end <= session.start { lower = mid + 1 } else { upper = mid }
        }
        var visits: [ActivitySlice] = []
        while lower < websites.count && websites[lower].start < session.end {
            let visit = websites[lower]
            let start = max(visit.start, session.start), end = min(visit.end, session.end)
            if end > start {
                visits.append(ActivitySlice(id: visit.id, kind: .website, key: visit.key, name: visit.name,
                    start: start, end: end, pageURL: visit.pageURL, pageTitle: visit.pageTitle))
            }
            lower += 1
        }
        return visits
    }

    func bucket(containing date: Date) -> UsageBucket? {
        buckets.first { date >= $0.interval.start && date < $0.interval.end }
    }
}
