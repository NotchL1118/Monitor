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
    /// Merged blocks starting or continuing on this day.
    let sessions: [ActivitySlice]
    /// Recorded foreground time on this day, excluding absorbed switches.
    let seconds: Double
    var id: Date { date }
}

struct ApplicationReport {
    let application: ActivityIdentity
    let period: ReportPeriod
    let interval: DateInterval
    let calendar: Calendar
    /// Blocks with brief switches (< 30 s) absorbed; see `SessionMerger`.
    let sessions: [ActivitySlice]
    let buckets: [UsageBucket]
    let days: [SessionDay]
    /// Recorded foreground time, excluding absorbed switches.
    let seconds: Double
    let interruptions: [Int64: Int]
    /// Two parts of a block split at midnight share a database ID but have distinct start times.
    let activeSeconds: [Date: Double]
    var longest: Double { sessions.map(\.seconds).max() ?? 0 }
    var peak: UsageBucket? { buckets.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds } }

    init(application: ActivityIdentity, period: ReportPeriod, interval: DateInterval,
         sessions: [ActivitySlice], now: Date = Date(), calendar: Calendar = ReportPeriod.calendar) {
        self.application = application
        self.period = period
        self.interval = interval
        self.calendar = calendar
        let end = min(interval.end, now)
        let clipped = sessions.compactMap { slice -> ActivitySlice? in
            guard slice.kind == .application, slice.key == application.key else { return nil }
            let start = max(slice.start, interval.start), stop = min(slice.end, end)
            guard start < stop else { return nil }
            return ActivitySlice(id: slice.id, kind: slice.kind, key: slice.key, name: slice.name, start: start, end: stop)
        }.sorted { $0.start < $1.start }
        seconds = clipped.reduce(0) { $0 + $1.seconds }
        let merged = SessionMerger.merge(clipped)
        self.sessions = merged.map(\.slice)
        interruptions = Dictionary(merged.map { ($0.slice.id, $0.interruptions) }, uniquingKeysWith: max)
        func byDay(_ slices: [ActivitySlice]) -> [Date: [ActivitySlice]] {
            var grouped: [Date: [ActivitySlice]] = [:]
            for slice in slices {
                var cursor = slice.start
                while cursor < slice.end {
                    let day = calendar.dateInterval(of: .day, for: cursor)!
                    let stop = min(slice.end, day.end)
                    grouped[day.start, default: []].append(ActivitySlice(id: slice.id, kind: slice.kind,
                        key: slice.key, name: slice.name, start: cursor, end: stop))
                    cursor = stop
                }
            }
            return grouped
        }
        let blocksByDay = byDay(self.sessions), rawByDay = byDay(clipped)
        var recordedByStart: [Date: Double] = [:]
        for (day, blocks) in blocksByDay {
            let raw = rawByDay[day, default: []]
            for block in blocks {
                let span = DateInterval(start: block.start, end: block.end)
                recordedByStart[block.start] = raw.overlapping(span).reduce(0) { $0 + $1.seconds }
            }
        }
        activeSeconds = recordedByStart
        days = blocksByDay.keys.sorted().map { day in
            SessionDay(date: day, sessions: blocksByDay[day]!, seconds: rawByDay[day, default: []].reduce(0) { $0 + $1.seconds })
        }

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

    func bucket(containing date: Date) -> UsageBucket? {
        buckets.first { date >= $0.interval.start && date < $0.interval.end }
    }
}
