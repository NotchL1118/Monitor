import Foundation

enum ReportTimeZone: String, CaseIterable {
    case system
    case utcPlus8

    static let preferenceKey = "reportTimeZone"

    var timeZone: TimeZone {
        switch self {
        case .system: return .autoupdatingCurrent
        case .utcPlus8: return TimeZone(secondsFromGMT: 8 * 3600)!
        }
    }

    var label: String {
        switch self {
        case .system: return "跟随系统时区"
        case .utcPlus8: return "北京时间（UTC+8）"
        }
    }

    var calendar: Calendar {
        var calendar = ReportPeriod.calendar
        calendar.timeZone = timeZone
        return calendar
    }

    var formatStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: timeZone)
    }
}
