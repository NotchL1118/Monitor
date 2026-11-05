import Foundation

/// One sector of the share ring. The largest items keep their own sector; the rest fold into "other".
public struct UsageShare: Identifiable, Equatable {
    public static let otherKey = "\u{0}other"

    public var id: String { key }
    public let key: String
    public let name: String
    public let seconds: Double
    /// Share of the total, 0...1.
    public let fraction: Double
    /// Cumulative share before this sector, 0...1, measured clockwise from 12 o'clock.
    public let start: Double
    /// Fixed color slot by rank (0 = largest). `nil` for the folded "other" sector.
    public let slot: Int?
    /// Number of items folded into the "other" sector; 0 for regular sectors.
    public let foldedCount: Int

    public var isOther: Bool { slot == nil }
    public var end: Double { start + fraction }
    public var middle: Double { start + fraction / 2 }

    /// Splits summaries into at most `limit` named sectors plus one "other" sector.
    /// Zero and negative durations are ignored. Ties keep the incoming order.
    public static func make(_ items: [UsageSummary], limit: Int = 5) -> [UsageShare] {
        let positive = items.enumerated().filter { $0.element.seconds > 0 }
            .sorted { $0.element.seconds != $1.element.seconds ? $0.element.seconds > $1.element.seconds : $0.offset < $1.offset }
            .map(\.element)
        let total = positive.reduce(0) { $0 + $1.seconds }
        guard total > 0, limit > 0 else { return [] }
        let named = positive.prefix(limit)
        let rest = positive.dropFirst(named.count)
        var shares: [UsageShare] = []
        var cursor = 0.0
        for (index, item) in named.enumerated() {
            let fraction = item.seconds / total
            shares.append(UsageShare(key: item.key, name: item.name, seconds: item.seconds, fraction: fraction,
                                     start: cursor, slot: index, foldedCount: 0))
            cursor += fraction
        }
        if !rest.isEmpty {
            let seconds = rest.reduce(0) { $0 + $1.seconds }
            shares.append(UsageShare(key: otherKey, name: "其他 \(rest.count) 项", seconds: seconds,
                                     fraction: max(0, 1 - cursor), start: cursor, slot: nil, foldedCount: rest.count))
        }
        return shares
    }

    /// The sector under a clockwise position measured from 12 o'clock, 0...1.
    public static func share(at position: Double, in shares: [UsageShare]) -> UsageShare? {
        let wrapped = position - floor(position)
        return shares.first { wrapped >= $0.start && wrapped < $0.end } ?? shares.last
    }

    /// Whole-percent text; shares under 1% read "<1%" instead of "0%".
    public static func percentText(_ fraction: Double) -> String {
        if fraction <= 0 { return "0%" }
        if fraction < 0.01 { return "<1%" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}
