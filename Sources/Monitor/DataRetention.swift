import Foundation

/// How long raw activity slices are kept on disk. Defaults to keeping everything.
enum DataRetention: String, CaseIterable {
    case oneMonth, threeMonths, sixMonths, oneYear, twoYears, forever

    static let preferenceKey = "dataRetention"

    var months: Int? {
        switch self {
        case .oneMonth: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .twoYears: return 24
        case .forever: return nil
        }
    }

    var label: String {
        switch self {
        case .oneMonth: return "最近 1 个月"
        case .threeMonths: return "最近 3 个月"
        case .sixMonths: return "最近 6 个月"
        case .oneYear: return "最近 1 年"
        case .twoYears: return "最近 2 年"
        case .forever: return "永久保留"
        }
    }

    var shortLabel: String {
        switch self {
        case .oneMonth: return "1 个月"
        case .threeMonths: return "3 个月"
        case .sixMonths: return "6 个月"
        case .oneYear: return "1 年"
        case .twoYears: return "2 年"
        case .forever: return "永久"
        }
    }

    /// Slices that ended at or before this instant are removed. Aligned to the start of a
    /// calendar day so a retained day is never partially deleted.
    func cutoff(now: Date, calendar: Calendar) -> Date? {
        guard let months else { return nil }
        return calendar.date(byAdding: .month, value: -months, to: calendar.startOfDay(for: now))
    }
}

/// On-disk footprint of the database, including its WAL and shared-memory files.
struct StorageUsage: Equatable {
    var bytes: Int64
    var earliest: Date?

    static func measure(databaseAt url: URL) -> Int64 {
        ["", "-wal", "-shm"].reduce(Int64(0)) { total, suffix in
            let path = url.path + suffix
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
