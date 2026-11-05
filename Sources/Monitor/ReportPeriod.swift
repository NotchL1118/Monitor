import Foundation

enum ReportPeriod: String, CaseIterable {
    case day = "日", week = "周", month = "月"

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    var currentLabel: String {
        switch self {
        case .day: return "今天"
        case .week: return "本周"
        case .month: return "本月"
        }
    }

    func interval(containing date: Date, calendar: Calendar = Self.calendar) -> DateInterval {
        calendar.dateInterval(of: component, for: date)!
    }

    func label(for date: Date, calendar: Calendar = Self.calendar) -> String {
        let span = interval(containing: date, calendar: calendar)
        let y = calendar.component(.year, from: span.start)
        let m = calendar.component(.month, from: span.start)
        let d = calendar.component(.day, from: span.start)
        let month = "\(y)年\(m)月"
        guard self != .month else { return month }
        let first = "\(month)\(d)日"
        guard self == .week else { return first }
        let last = calendar.date(byAdding: .day, value: -1, to: span.end)!
        let endYear = calendar.component(.year, from: last)
        let endMonth = calendar.component(.month, from: last)
        let endDay = calendar.component(.day, from: last)
        if endYear != y { return "\(first) – \(endYear)年\(endMonth)月\(endDay)日" }
        if endMonth != m { return "\(first) – \(endMonth)月\(endDay)日" }
        return "\(first) – \(endDay)日"
    }
}
