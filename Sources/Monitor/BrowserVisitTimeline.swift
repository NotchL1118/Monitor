import Foundation
import MonitorCore

/// Display geometry uses elapsed wall time. Visit durations and identities come from the report.
struct BrowserVisitTimeline {
    struct Lane: Identifiable {
        let domain: String
        let visits: [ActivitySlice]
        let runs: [DateInterval]
        var id: String { domain }
    }

    enum Row: Identifiable {
        case visit(ActivitySlice)
        case gap(DateInterval)

        var id: Date {
            switch self {
            case .visit(let visit): return visit.start
            case .gap(let interval): return interval.start
            }
        }
    }

    let interval: DateInterval
    let visits: [ActivitySlice]
    let rows: [Row]
    let lanes: [Lane]
    let domainSlots: [String: Int]
    let missingSeconds: Double
    /// False when `visits` is a filtered subset, so the space between them is not "无页面记录".
    let showsGaps: Bool

    /// The report supplies chronological, non-overlapping visits clipped to this session.
    init(session: ActivitySlice, visits: [ActivitySlice], activeSeconds: Double, showsGaps: Bool = true) {
        interval = DateInterval(start: session.start, end: session.end)
        self.showsGaps = showsGaps
        self.visits = visits
        var rows: [Row] = []
        var slots: [String: Int] = [:]
        var cursor = session.start
        var recorded: Double = 0
        for visit in visits {
            if showsGaps && visit.start.timeIntervalSince(cursor) >= 5 {
                rows.append(.gap(DateInterval(start: cursor, end: visit.start)))
            }
            rows.append(.visit(visit))
            if slots[visit.key] == nil { slots[visit.key] = slots.count }
            recorded += visit.seconds
            cursor = visit.end
        }
        if showsGaps && session.end.timeIntervalSince(cursor) >= 5 {
            rows.append(.gap(DateInterval(start: cursor, end: session.end)))
        }
        self.rows = rows
        domainSlots = slots
        let grouped = Dictionary(grouping: visits.indices) { visits[$0].key }
        lanes = slots.sorted { $0.value < $1.value }.map { domain, _ in
            let indices = grouped[domain, default: []]
            var runs: [DateInterval] = []
            for index in indices {
                let visit = visits[index]
                // Only the site band's paint bridges subsecond gaps. Check the previous visit
                // in global order so a switch to another site always breaks the band.
                if index > 0, visits[index - 1].key == domain,
                   visit.start.timeIntervalSince(visits[index - 1].end) < 1, let last = runs.indices.last {
                    runs[last].end = visit.end
                } else {
                    runs.append(DateInterval(start: visit.start, end: visit.end))
                }
            }
            return Lane(domain: domain, visits: indices.map { visits[$0] }, runs: runs)
        }
        missingSeconds = showsGaps ? max(0, min(session.seconds, activeSeconds) - recorded) : 0
    }

    /// Use half-open intervals so adjacent visits never both claim the same boundary.
    func fractions(for visit: ActivitySlice) -> Range<Double>? {
        fractions(for: DateInterval(start: visit.start, end: visit.end))
    }

    func fractions(for span: DateInterval) -> Range<Double>? {
        let start = max(span.start, interval.start), end = min(span.end, interval.end)
        guard start < end else { return nil }
        return (start.timeIntervalSince(interval.start) / interval.duration)..<(end.timeIntervalSince(interval.start) / interval.duration)
    }
}

extension Array where Element == ActivitySlice {
    /// For chronological, non-overlapping records, seek to the first possible match before scanning.
    func overlapping(_ interval: DateInterval) -> ArraySlice<ActivitySlice> {
        var lower = startIndex, upper = endIndex
        while lower < upper {
            let mid = lower + (upper - lower) / 2
            if self[mid].end > interval.start { upper = mid } else { lower = mid + 1 }
        }
        return self[lower...].prefix { $0.start < interval.end }
    }
}
