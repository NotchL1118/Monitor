import Foundation
import MonitorCore

struct TimelineSegment: Identifiable {
    let start: Date
    let end: Date
    let activity: ActivitySlice?
    var id: Date { start }
    var seconds: Double { end.timeIntervalSince(start) }
}

struct TimelineLane: Identifiable {
    let interval: DateInterval
    var segments: [TimelineSegment]
    var id: Date { interval.start }
    var empty: Bool { segments.allSatisfy { $0.activity == nil } }
}

struct DayTimelineReport {
    let interval: DateInterval
    let elapsedEnd: Date
    let sessions: [ActivitySlice]
    let lanes: [TimelineLane]
    var seconds: Double { sessions.reduce(0) { $0 + $1.seconds } }

    init(date: Date, calendar: Calendar, sessions: [ActivitySlice], hoursPerLane: Int = 4, now: Date = Date()) {
        interval = calendar.dateInterval(of: .day, for: date)!
        elapsedEnd = max(interval.start, min(now, interval.end))
        let start = interval.start, end = elapsedEnd
        self.sessions = sessions.filter { $0.kind == .application }.compactMap { slice in
            let a = max(start, slice.start), b = min(end, slice.end)
            guard a < b else { return nil }
            return ActivitySlice(id: slice.id, kind: .application, key: slice.key, name: slice.name, start: a, end: b)
        }.sorted { $0.start < $1.start }
        var result: [TimelineLane] = []
        var cursor = start
        // Calendar hours preserve elapsed time on DST transitions, including a repeated hour.
        while cursor < end {
            let laneEnd = min(calendar.date(byAdding: .hour, value: max(1, hoursPerLane), to: cursor)!, interval.end)
            let next = min(laneEnd, end)
            var segments: [TimelineSegment] = []
            var position = cursor
            for session in self.sessions where session.start < next && session.end > cursor {
                let a = max(position, session.start), b = min(next, session.end)
                guard a < b else { continue }
                if position < a { segments.append(TimelineSegment(start: position, end: a, activity: nil)) }
                segments.append(TimelineSegment(start: a, end: b, activity: session))
                position = b
            }
            if position < next { segments.append(TimelineSegment(start: position, end: next, activity: nil)) }
            let isEmpty = segments.allSatisfy { $0.activity == nil }
            let lane = TimelineLane(interval: DateInterval(start: cursor, end: isEmpty ? next : laneEnd), segments: segments)
            if lane.empty, let last = result.last, last.empty {
                result[result.count - 1] = TimelineLane(interval: DateInterval(start: last.interval.start, end: next),
                    segments: [TimelineSegment(start: last.interval.start, end: next, activity: nil)])
            } else { result.append(lane) }
            cursor = next
        }
        lanes = result
    }
}
