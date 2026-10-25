import Foundation

/// 所有区间使用“包含起点、不包含终点”，避免午夜记录被重复计算。
public enum RunPeriod: String, CaseIterable, Identifiable {
    case week = "周", month = "月", quarter = "季度", year = "年"
    public var id: String { rawValue }
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        if self == .quarter {
            let parts = calendar.dateComponents([.year, .month], from: date)
            let month = ((parts.month! - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: parts.year, month: month, day: 1))!
            return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 3, to: start)!)
        }
        let component: Calendar.Component = self == .week ? .weekOfYear : self == .month ? .month : .year
        return calendar.dateInterval(of: component, for: date)!
    }
    public func shifted(_ date: Date, by offset: Int, calendar: Calendar) -> Date {
        let component: Calendar.Component = self == .week ? .weekOfYear : self == .year ? .year : .month
        return calendar.date(byAdding: component, value: self == .quarter ? offset * 3 : offset,
                             to: interval(containing: date, calendar: calendar).start)!
    }
    /// 周、月按日展示；季度、年按月汇总，保持图表可读。
    public func buckets(containing date: Date, calendar: Calendar) -> [DateInterval] {
        let range = interval(containing: date, calendar: calendar)
        let component: Calendar.Component = self == .week || self == .month ? .day : .month
        var cursor = range.start
        var result: [DateInterval] = []
        while cursor < range.end {
            let end = min(calendar.date(byAdding: component, value: 1, to: cursor)!, range.end)
            result.append(DateInterval(start: cursor, end: end)); cursor = end
        }
        return result
    }
}

public struct RunSummary {
    public let count: Int
    public let duration: TimeInterval
    public let distance: Double
    public let pace: Double?
    public init(records: [RunRecord], interval: DateInterval) {
        let selected = records.filter { $0.date >= interval.start && $0.date < interval.end }
        count = selected.count
        duration = selected.reduce(0) { $0 + $1.duration }
        distance = selected.reduce(0) { $0 + $1.distance }
        // 未填写距离的记录不参与配速，避免把仅有时长的跑步计入分母。
        let measured = selected.filter { $0.distance > 0 }
        let measuredDistance = measured.reduce(0) { $0 + $1.distance }
        pace = measuredDistance > 0 ? measured.reduce(0) { $0 + $1.duration } / measuredDistance : nil
    }
}

public enum RunStatistics {
    /// 本周尚未跑步时仍保留截至上周的连续周数；断开一个完整周才清零。
    public static func weekStreak(records: [RunRecord], now: Date, calendar: Calendar) -> Int {
        let starts = Set(records.map { RunPeriod.week.interval(containing: $0.date, calendar: calendar).start })
        var cursor = RunPeriod.week.interval(containing: now, calendar: calendar).start
        if !starts.contains(cursor) { cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor)! }
        var count = 0
        while starts.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor)!
        }
        return count
    }
}
