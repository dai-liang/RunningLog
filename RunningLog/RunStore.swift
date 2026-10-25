import SwiftUI

/// 文件写入成功后再发布状态，写盘失败时界面仍与磁盘保持一致。
@MainActor
final class RunStore: ObservableObject {
    @Published private(set) var records: [RunRecord] = []
    @Published private(set) var settings = RunSettings()
    @Published var errorMessage: String?
    @Published private(set) var storageAvailable = true
    private let fileURL: URL

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = settings.mondayFirst ? 2 : 1
        calendar.minimumDaysInFirstWeek = settings.mondayFirst ? 4 : 1
        return calendar
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RunningLog", isDirectory: true)
        fileURL = directory.appendingPathComponent("runs.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let archive = try JSONDecoder().decode(RunArchive.self, from: Data(contentsOf: fileURL))
                try archive.validate()
                records = archive.records.sorted { $0.date > $1.date }; settings = archive.settings
            }
        } catch {
            // 读取失败时锁定写入，保护原始文件，避免空数组覆盖用户历史记录。
            storageAvailable = false
            errorMessage = "无法读取本地数据，已暂停写入以保护原文件。\n\(error.localizedDescription)"
        }
    }

    private func persist(records: [RunRecord], settings: RunSettings) throws {
        guard storageAvailable else { throw RunError.invalid("本地数据读取失败，请先保留应用数据并检查存储文件。") }
        let archive = RunArchive(records: records, settings: settings)
        try archive.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: fileURL, options: .atomic)
        self.records = records.sorted { $0.date > $1.date }; self.settings = settings
    }

    func save(_ record: RunRecord) throws {
        try record.validate()
        var updated = records
        if let index = updated.firstIndex(where: { $0.id == record.id }) { updated[index] = record }
        else { updated.append(record) }
        try persist(records: updated, settings: settings)
    }

    func delete(_ record: RunRecord) {
        do { try persist(records: records.filter { $0.id != record.id }, settings: settings) }
        catch { errorMessage = error.localizedDescription }
    }

    func updateSettings(_ settings: RunSettings) {
        do { try persist(records: records, settings: settings) }
        catch { errorMessage = error.localizedDescription }
    }

    /// 导入按 UUID 合并，同编号以备份为准；保留本机目标及显示偏好。
    func importBackup(_ data: Data) throws -> Int {
        guard data.count <= 20_000_000 else { throw RunError.invalid("备份不能超过 20 MB。") }
        let archive = try JSONDecoder().decode(RunArchive.self, from: data)
        try archive.validate()
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in archive.records { merged[record.id] = record }
        try persist(records: Array(merged.values), settings: settings)
        return archive.records.count
    }

    func backup() throws -> Data {
        guard storageAvailable else { throw RunError.invalid("本地数据读取失败，暂时无法导出。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(RunArchive(records: records, settings: settings))
    }
}

/// 集中格式化时长与配速，保证概览、列表、详情的口径一致。
enum RunFormat {
    /// 概览使用时分秒，避免将短跑时长四舍五入成整分钟。
    static func clock(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%d:%02d:%02d", value / 3600, value % 3600 / 60, value % 60)
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分 \(Int(seconds) % 60) 秒"
    }
    static func pace(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let rounded = Int(seconds.rounded())
        return String(format: "%d′%02d″", rounded / 60, rounded % 60)
    }
}
