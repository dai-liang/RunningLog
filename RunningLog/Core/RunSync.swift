import Foundation

/// 同步单元：删除时保留带版本的墓碑，使离线设备不会重新上传已删除记录。
public struct RunSyncEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var record: RunRecord?
    public var modifiedAt: Date
    public var revision: String

    public init(id: UUID, record: RunRecord?, modifiedAt: Date = Date(), revision: String = UUID().uuidString) {
        self.id = id; self.record = record; self.modifiedAt = modifiedAt; self.revision = revision
    }
    public func validate() throws {
        guard modifiedAt.timeIntervalSince1970.isFinite, modifiedAt >= Date(timeIntervalSince1970: 0),
              modifiedAt <= Date(timeIntervalSince1970: 253_402_300_799),
              !revision.isEmpty, revision.count <= 128, record == nil || record?.id == id else {
            throw RunError.invalid("同步记录的编号或版本信息无效。")
        }
        try record?.validate()
    }
    public func isNewer(than other: RunSyncEntry) -> Bool {
        modifiedAt == other.modifiedAt ? revision > other.revision : modifiedAt > other.modifiedAt
    }
    /// 每批数据先完整校验再合并；以时间及修订号形成确定顺序，结果与设备读取顺序无关。
    public static func merge(_ local: [RunSyncEntry], _ remote: [RunSyncEntry]) throws -> [RunSyncEntry] {
        for batch in [local, remote] {
            guard Set(batch.map(\.id)).count == batch.count else { throw RunError.invalid("同步数据包含重复编号。") }
            for entry in batch { try entry.validate() }
        }
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for entry in remote {
            if let existing = merged[entry.id] {
                guard existing.modifiedAt != entry.modifiedAt || existing.revision != entry.revision || existing == entry else {
                    throw RunError.invalid("同一同步版本包含不同内容，已停止同步以保护数据。")
                }
                if entry.isNewer(than: existing) { merged[entry.id] = entry }
            } else { merged[entry.id] = entry }
        }
        return merged.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// 同步元数据与跑步记录在同一个文件中原子保存，崩溃或离线后仍可重试。
public struct RunSyncState: Codable, Equatable {
    public var entries: [RunSyncEntry]
    public var enabled = false
    public var accountID: String?
    public var lastSyncedAt: Date?

    public init(records: [RunRecord]) {
        // 旧版记录使用固定的初始版本，防止新安装设备把旧备份当成较新的编辑。
        entries = records.map { RunSyncEntry(id: $0.id, record: $0, modifiedAt: Date(timeIntervalSince1970: 0), revision: "legacy") }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public var records: [RunRecord] {
        entries.compactMap(\.record).sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
    public func validate(records: [RunRecord]) throws {
        if let accountID, accountID.isEmpty || accountID.count > 1024 {
            throw RunError.invalid("同步账号标记无效。")
        }
        if let date = lastSyncedAt {
            guard date.timeIntervalSince1970.isFinite, date >= Date(timeIntervalSince1970: 0),
                  date <= Date(timeIntervalSince1970: 253_402_300_799) else {
                throw RunError.invalid("最近同步时间无效。")
            }
        }
        guard Set(records.map(\.id)).count == records.count else { throw RunError.invalid("跑步记录包含重复编号。") }
        _ = try RunSyncEntry.merge(entries, [])
        guard Dictionary(uniqueKeysWithValues: self.records.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }) else {
            throw RunError.invalid("跑步记录与同步索引不一致，已停止写入。")
        }
    }
    /// 本机时间回拨时也保持单条记录的版本单调递增。
    public mutating func change(id: UUID, record: RunRecord?, now: Date = Date()) {
        let old = entries.first { $0.id == id }
        let timestamp = max(now, (old?.modifiedAt ?? Date(timeIntervalSince1970: 0)).addingTimeInterval(0.001))
        entries.removeAll { $0.id == id }
        entries.append(RunSyncEntry(id: id, record: record, modifiedAt: timestamp))
        entries.sort { $0.id.uuidString < $1.id.uuidString }
    }
}
