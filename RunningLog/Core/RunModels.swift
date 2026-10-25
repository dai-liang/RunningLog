import Foundation

/// 一次手动记录；时长统一存秒、距离统一存公里，避免界面单位影响统计。
public struct RunRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var duration: TimeInterval
    public var distance: Double
    public var feeling: RunFeeling
    public var note: String

    public init(id: UUID = UUID(), date: Date = Date(), duration: TimeInterval = 1800,
                distance: Double = 0, feeling: RunFeeling = .good, note: String = "") {
        self.id = id; self.date = date; self.duration = duration
        self.distance = distance; self.feeling = feeling; self.note = note
    }

    /// 新增、编辑和导入共用校验，确保异常数据不会绕过表单进入统计。
    public func validate(now: Date = Date()) throws {
        // 限制极端历史日期，防止外部 JSON 中的异常时间超出日历可计算范围。
        guard date.timeIntervalSince1970.isFinite,
              date >= Date(timeIntervalSince1970: -2_208_988_800), date <= now else {
            throw RunError.invalid("跑步日期需在 1900 年至当前时间之间。")
        }
        guard duration.isFinite, duration >= 1, duration <= 86400 else {
            throw RunError.invalid("跑步时长需至少 1 秒，且不超过 24 小时。")
        }
        guard distance.isFinite, distance >= 0, distance <= 500 else {
            throw RunError.invalid("距离需在 0～500 公里之间；不填距离可记为 0。")
        }
        guard note.count <= 2000 else { throw RunError.invalid("备注最多 2000 字。") }
    }
}

/// 主观感受用于回顾训练状态，不代替医疗或运动指导。
public enum RunFeeling: String, Codable, CaseIterable, Identifiable {
    case easy = "轻松", good = "适中", hard = "吃力"
    public var id: String { rawValue }
    public var symbol: String {
        switch self { case .easy: return "sun.max"; case .good: return "face.smiling"; case .hard: return "flame" }
    }
}

public struct RunSettings: Codable, Equatable {
    public var weeklyCount = 3
    public var weeklyMinutes = 120
    public var mondayFirst = true
    /// 0 跟随系统，1 浅色，2 深色。
    public var appearance = 0
    public init() {}
    public func validate() throws {
        guard (1...21).contains(weeklyCount), (10...3000).contains(weeklyMinutes),
              (0...2).contains(appearance) else { throw RunError.invalid("备份中的设置超出允许范围。") }
    }
}

/// 带版本的数据包同时用于本地存储和备份，未来升级可以显式迁移。
public struct RunArchive: Codable {
    public var version = 1
    public var records: [RunRecord]
    public var settings: RunSettings
    public init(records: [RunRecord], settings: RunSettings) { self.records = records; self.settings = settings }
    public func validate() throws {
        guard version == 1 else { throw RunError.invalid("此备份版本暂不支持，请使用版本 1 的备份。") }
        guard Set(records.map(\.id)).count == records.count else { throw RunError.invalid("备份包含重复的记录编号。") }
        try settings.validate()
        for record in records { try record.validate() }
    }
}

public enum RunError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
