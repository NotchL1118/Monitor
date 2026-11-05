import Foundation

/// Display-only smoothing: brief switches away (e.g. glancing at a message) don't split a block of work.
/// Raw slices in the store are never rewritten; totals should still be computed from raw slices.
public enum SessionMerger {
    public static let interruptionThreshold: TimeInterval = 30

    public struct Session {
        /// Spans from the first to the last merged slice; `id` is the first slice's id.
        public var slice: ActivitySlice
        /// Foreground time actually recorded for this identity inside the span.
        public var activeSeconds: Double
        /// Short switches or unrecorded gaps absorbed into the span.
        public var interruptions: Int
    }

    /// `slices` must be non-overlapping. A slice rejoins the latest block with the same key when it starts
    /// less than `threshold` after that block ended; everything in between (other apps or gaps, all shorter
    /// than the threshold in total) is absorbed into the block.
    public static func merge(_ slices: [ActivitySlice], threshold: TimeInterval = interruptionThreshold) -> [Session] {
        var result: [Session] = []
        for slice in slices.sorted(by: { $0.start < $1.start }) where slice.end > slice.start {
            var match: Int?
            var index = result.count - 1
            while index >= 0, slice.start.timeIntervalSince(result[index].slice.end) < threshold {
                if result[index].slice.key == slice.key && result[index].slice.kind == slice.kind { match = index; break }
                index -= 1
            }
            if let match {
                var block = result[match]
                let gap = slice.start.timeIntervalSince(block.slice.end)
                block.slice = ActivitySlice(id: block.slice.id, kind: block.slice.kind, key: block.slice.key, name: slice.name,
                    start: block.slice.start, end: max(block.slice.end, slice.end))
                block.activeSeconds += slice.seconds
                block.interruptions += result.count - 1 - match + (gap > 0.5 && match == result.count - 1 ? 1 : 0)
                result.removeSubrange(match...)
                result.append(block)
            } else {
                result.append(Session(slice: ActivitySlice(id: slice.id, kind: slice.kind, key: slice.key, name: slice.name,
                    start: slice.start, end: slice.end), activeSeconds: slice.seconds, interruptions: 0))
            }
        }
        return result
    }
}
