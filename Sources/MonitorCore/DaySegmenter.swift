import Foundation

/// Display-only grouping of one day's application slices into readable periods ("时段").
///
/// The day is first split wherever the user was away (a recorded gap of at least `awayThreshold`).
/// Each stretch of presence is cut into fixed buckets; neighbouring buckets whose app mix overlaps by at
/// least `similarity` are merged, and periods shorter than `minimumSegment` are folded into the more
/// similar neighbour. Raw slices are never rewritten: totals must still come from the raw slices.
public enum DaySegmenter {
    public struct Parameters: Equatable {
        /// Analysis bucket length.
        public var bucket: TimeInterval
        /// A gap at least this long between two uses is shown as "离开".
        public var awayThreshold: TimeInterval
        /// Minimum overlap (0...1) of two app mixes for them to stay in one period.
        public var similarity: Double
        /// Periods with less active time than this are folded into a neighbour.
        public var minimumSegment: TimeInterval
        /// Isolated use shorter than this between two absences is folded into the absence.
        public var briefUse: TimeInterval

        public init(bucket: TimeInterval = 300, awayThreshold: TimeInterval = 600, similarity: Double = 0.45,
                    minimumSegment: TimeInterval = 600, briefUse: TimeInterval = 120) {
            self.bucket = bucket; self.awayThreshold = awayThreshold; self.similarity = similarity
            self.minimumSegment = minimumSegment; self.briefUse = briefUse
        }
    }

    public enum Focus: Equatable { case focused, mixed, fragmented }

    public struct Share: Identifiable, Equatable {
        public let key: String
        public let name: String
        public var seconds: Double
        /// Number of separate uses (runs) inside the period.
        public var uses: Int
        public var id: String { key }
    }

    public struct Segment: Identifiable {
        public let start: Date
        public let end: Date
        /// Consecutive uses of one app merged and clipped to the period, in time order.
        public let runs: [ActivitySlice]
        /// Apps by active time, descending.
        public let apps: [Share]
        /// Websites (clipped to the period) by time, descending.
        public let websites: [Share]
        public let activeSeconds: Double
        public let switches: Int
        public let focus: Focus
        public var id: Date { start }
        public var span: Double { end.timeIntervalSince(start) }
        public func share(of app: Share) -> Double { activeSeconds > 0 ? app.seconds / activeSeconds : 0 }
    }

    public struct Away: Identifiable, Equatable {
        public let start: Date
        public let end: Date
        /// Foreground time of brief uses folded into this absence.
        public let briefSeconds: Double
        public var id: Date { start }
        public var seconds: Double { end.timeIntervalSince(start) }
    }

    public enum Block: Identifiable {
        case segment(Segment)
        case away(Away)
        public var start: Date { switch self { case .segment(let s): s.start; case .away(let a): a.start } }
        public var end: Date { switch self { case .segment(let s): s.end; case .away(let a): a.end } }
        public var id: Date { start }
        public var segment: Segment? { if case .segment(let s) = self { s } else { nil } }
    }

    /// Joins consecutive slices of the same app separated by at most `tolerance` into one use.
    public static func runs(_ slices: [ActivitySlice], tolerance: TimeInterval = 3) -> [ActivitySlice] {
        var result: [ActivitySlice] = []
        for slice in slices.sorted(by: { $0.start < $1.start }) where slice.end > slice.start {
            if let last = result.last, last.key == slice.key, slice.start.timeIntervalSince(last.end) <= tolerance {
                result[result.count - 1] = ActivitySlice(id: last.id, kind: last.kind, key: last.key, name: slice.name,
                    start: last.start, end: max(last.end, slice.end))
            } else { result.append(slice) }
        }
        return result
    }

    /// `applications` must be non-overlapping application slices; `origin` aligns buckets (use the day start).
    public static func blocks(applications: [ActivitySlice], websites: [ActivitySlice] = [], origin: Date,
                              parameters p: Parameters = Parameters()) -> [Block] {
        let runs = runs(applications.filter { $0.kind == .application })
        guard !runs.isEmpty else { return [] }
        var groups: [[ActivitySlice]] = [[runs[0]]]
        for run in runs.dropFirst() {
            if run.start.timeIntervalSince(groups[groups.count - 1].last!.end) >= p.awayThreshold { groups.append([]) }
            groups[groups.count - 1].append(run)
        }
        let sites = websites.filter { $0.kind == .website }.sorted { $0.start < $1.start }
        var blocks: [Block] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { blocks.append(.away(Away(start: groups[index - 1].last!.end, end: group[0].start, briefSeconds: 0))) }
            blocks += split(group, websites: sites, origin: origin, parameters: p).map(Block.segment)
        }
        return foldBriefUse(blocks, below: p.briefUse)
    }

    // MARK: - Internals

    private struct Draft { var start: Date; var end: Date; var mix: [String: Double] }

    private static func split(_ runs: [ActivitySlice], websites: [ActivitySlice], origin: Date, parameters p: Parameters) -> [Segment] {
        let bucket = max(60, p.bucket)
        let first = runs[0].start, last = runs[runs.count - 1].end
        var t = origin.addingTimeInterval((first.timeIntervalSince(origin) / bucket).rounded(.down) * bucket)
        var drafts: [Draft] = []
        var current: Draft?
        var cursor = 0
        while t < last {
            let next = t.addingTimeInterval(bucket)
            while cursor < runs.count, runs[cursor].end <= t { cursor += 1 }
            var mix: [String: Double] = [:]
            var index = cursor
            while index < runs.count, runs[index].start < next {
                let a = max(t, runs[index].start), b = min(next, runs[index].end)
                if b > a { mix[runs[index].key, default: 0] += b.timeIntervalSince(a) }
                index += 1
            }
            if mix.isEmpty { current?.end = next }
            else if var draft = current, similarity(draft.mix, mix) >= p.similarity {
                draft.end = next; draft.mix.merge(mix, uniquingKeysWith: +); current = draft
            } else {
                if let draft = current { drafts.append(draft) }
                current = Draft(start: t, end: next, mix: mix)
            }
            t = next
        }
        if let draft = current { drafts.append(draft) }

        func join(_ lo: Int) {
            let merged = Draft(start: drafts[lo].start, end: drafts[lo + 1].end,
                               mix: drafts[lo].mix.merging(drafts[lo + 1].mix, uniquingKeysWith: +))
            drafts.replaceSubrange(lo...(lo + 1), with: [merged])
        }
        while drafts.count > 1 {
            // Neighbours that look alike once whole (e.g. after a short burst was absorbed) become one period.
            if let lo = drafts.indices.dropLast().first(where: { similarity(drafts[$0].mix, drafts[$0 + 1].mix) >= p.similarity }) {
                join(lo); continue
            }
            let short = drafts.indices.filter { total(drafts[$0].mix) < p.minimumSegment }
            guard let index = short.min(by: { total(drafts[$0].mix) < total(drafts[$1].mix) }) else { break }
            let neighbour: Int
            if index == 0 { neighbour = 1 }
            else if index == drafts.count - 1 { neighbour = index - 1 }
            else {
                neighbour = similarity(drafts[index - 1].mix, drafts[index].mix) >= similarity(drafts[index + 1].mix, drafts[index].mix)
                    ? index - 1 : index + 1
            }
            join(min(index, neighbour))
        }
        return drafts.compactMap { describe(start: max($0.start, first), end: min($0.end, last), runs: runs, websites: websites) }
    }

    private static func describe(start: Date, end: Date, runs: [ActivitySlice], websites: [ActivitySlice]) -> Segment? {
        let clipped = clip(runs, start, end)
        guard let first = clipped.first, let last = clipped.last else { return nil }
        var apps: [String: Share] = [:]
        for run in clipped {
            apps[run.key, default: Share(key: run.key, name: run.name, seconds: 0, uses: 0)].seconds += run.seconds
            apps[run.key]?.uses += 1
        }
        var sites: [String: Share] = [:]
        for visit in clip(websites, first.start, last.end) {
            sites[visit.key, default: Share(key: visit.key, name: visit.name, seconds: 0, uses: 0)].seconds += visit.seconds
            sites[visit.key]?.uses += 1
        }
        let ranked = apps.values.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.key < $1.key }
        let active = ranked.reduce(0) { $0 + $1.seconds }
        let switches = clipped.count - 1
        let perHour = Double(switches) / max(active / 3600, 1.0 / 6)
        let lead = active > 0 ? ranked[0].seconds / active : 0
        let focus: Focus = lead >= 0.7 && perHour < 40 ? .focused : (lead < 0.45 || perHour > 90 ? .fragmented : .mixed)
        return Segment(start: first.start, end: last.end, runs: clipped, apps: ranked,
            websites: sites.values.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.key < $1.key },
            activeSeconds: active, switches: switches, focus: focus)
    }

    private static func foldBriefUse(_ input: [Block], below limit: TimeInterval) -> [Block] {
        var blocks = input
        var index = 0
        while index < blocks.count {
            guard let segment = blocks[index].segment, segment.activeSeconds < limit else { index += 1; continue }
            let left = index > 0 ? away(blocks[index - 1]) : nil
            let right = index + 1 < blocks.count ? away(blocks[index + 1]) : nil
            guard left != nil || right != nil else { index += 1; continue }
            let brief = (left?.briefSeconds ?? 0) + (right?.briefSeconds ?? 0) + segment.activeSeconds
            let from = left == nil ? index : index - 1, to = right == nil ? index : index + 1
            blocks.replaceSubrange(from...to, with: [.away(Away(start: left?.start ?? segment.start,
                                                                 end: right?.end ?? segment.end, briefSeconds: brief))])
            index = from
        }
        return blocks
    }

    private static func away(_ block: Block) -> Away? { if case .away(let a) = block { a } else { nil } }

    private static func clip(_ slices: [ActivitySlice], _ start: Date, _ end: Date) -> [ActivitySlice] {
        slices.compactMap { slice in
            let a = max(start, slice.start), b = min(end, slice.end)
            guard a < b else { return nil }
            return ActivitySlice(id: slice.id, kind: slice.kind, key: slice.key, name: slice.name, start: a, end: b,
                                 pageURL: slice.pageURL, pageTitle: slice.pageTitle)
        }
    }

    private static func total(_ mix: [String: Double]) -> Double { mix.values.reduce(0, +) }

    /// Overlap of two app mixes: Σ min(shareA, shareB), in 0...1.
    static func similarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let ta = total(a), tb = total(b)
        guard ta > 0, tb > 0 else { return 0 }
        return a.reduce(0) { sum, item in sum + min(item.value / ta, (b[item.key] ?? 0) / tb) }
    }
}
