import Foundation
import MonitorCore

/// One overview row: a top app, or everything else folded together (`key == nil`).
struct DayTimelineLane: Identifiable {
    let key: String?
    let name: String
    let seconds: Double
    let runs: [ActivitySlice]
    var id: String { key ?? "" }
}

struct DayTimelineReport {
    static let colorSlots = 7
    static let laneCount = 5

    let interval: DateInterval
    let elapsedEnd: Date
    /// Periods and absences; display-only, see `DaySegmenter`.
    let blocks: [DaySegmenter.Block]
    /// Raw recorded foreground time.
    let seconds: Double
    let switches: Int
    let firstActivity: Date?
    let lastActivity: Date?
    /// Whole hours covering the recorded activity; the overview axis.
    let range: DateInterval
    let lanes: [DayTimelineLane]
    /// Color slot per app. Apps outside the day's top slots have none and are drawn as "其他".
    let colors: [String: Int]

    var segments: [DaySegmenter.Segment] { blocks.compactMap(\.segment) }
    var awayCount: Int { blocks.count - segments.count }

    init(date: Date, calendar: Calendar, activities: [ActivitySlice], now: Date = Date(),
         parameters: DaySegmenter.Parameters = DaySegmenter.Parameters()) {
        interval = calendar.dateInterval(of: .day, for: date)!
        elapsedEnd = max(interval.start, min(now, interval.end))
        let start = interval.start, end = elapsedEnd
        let clipped = activities.compactMap { slice -> ActivitySlice? in
            let a = max(start, slice.start), b = min(end, slice.end)
            guard a < b else { return nil }
            return ActivitySlice(id: slice.id, kind: slice.kind, key: slice.key, name: slice.name, start: a, end: b,
                                 pageURL: slice.pageURL, pageTitle: slice.pageTitle)
        }
        let applications = clipped.filter { $0.kind == .application }
        seconds = applications.reduce(0) { $0 + $1.seconds }
        let runs = DaySegmenter.runs(applications)
        switches = max(0, runs.count - 1)
        firstActivity = runs.first?.start
        lastActivity = runs.map(\.end).max()
        blocks = DaySegmenter.blocks(applications: applications, websites: clipped.filter { $0.kind == .website },
                                     origin: start, parameters: parameters)

        if let first = firstActivity, let last = lastActivity {
            let lower = calendar.dateInterval(of: .hour, for: first)!.start
            let upperHour = calendar.dateInterval(of: .hour, for: last)!
            let upper = upperHour.start == last ? last : min(upperHour.end, interval.end)
            range = DateInterval(start: lower, end: max(upper, lower.addingTimeInterval(3600)))
        } else { range = DateInterval(start: start, duration: 0) }

        var totals: [String: (name: String, seconds: Double)] = [:]
        for run in runs { totals[run.key, default: (run.name, 0)].seconds += run.seconds }
        let ranked = totals.sorted { $0.value.seconds != $1.value.seconds ? $0.value.seconds > $1.value.seconds : $0.key < $1.key }
        // Each app prefers a slot derived from its bundle id so its color stays the same across days.
        var colors: [String: Int] = [:]
        var taken = Set<Int>()
        for (key, _) in ranked.prefix(Self.colorSlots) {
            var slot = Self.preferredSlot(key)
            while taken.contains(slot) { slot = (slot + 1) % Self.colorSlots }
            taken.insert(slot); colors[key] = slot
        }
        self.colors = colors
        let top = ranked.prefix(Self.laneCount)
        var lanes = top.map { key, value in
            DayTimelineLane(key: key, name: value.name, seconds: value.seconds, runs: runs.filter { $0.key == key })
        }
        let topKeys = Set(top.map(\.key))
        let rest = runs.filter { !topKeys.contains($0.key) }
        if !rest.isEmpty {
            lanes.append(DayTimelineLane(key: nil, name: "其他 \(ranked.count - top.count) 个",
                                         seconds: rest.reduce(0) { $0 + $1.seconds }, runs: rest))
        }
        self.lanes = lanes
    }

    static func preferredSlot(_ key: String) -> Int {
        key.utf8.reduce(0) { ($0 * 31 + Int($1)) % 9973 } % colorSlots
    }

    static func title(_ segment: DaySegmenter.Segment) -> String {
        guard let lead = segment.apps.first else { return "" }
        if segment.share(of: lead) >= 0.6 || segment.apps.count < 2 { return lead.name }
        return "\(lead.name) + \(segment.apps[1].name)"
    }

    /// The block covering `date`, if any.
    func block(at date: Date) -> DaySegmenter.Block? {
        blocks.first { $0.start <= date && date <= $0.end }
    }

    /// The app in the foreground at `date`, if recorded.
    func application(at date: Date) -> ActivitySlice? {
        for lane in lanes { if let run = lane.runs.first(where: { $0.start <= date && date < $0.end }) { return run } }
        return nil
    }
}
