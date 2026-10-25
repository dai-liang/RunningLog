import SwiftUI

/// 本机优先：同步元数据与记录一并原子落盘，云端失败不会阻止新增和编辑。
@MainActor
final class RunStore: ObservableObject {
    @Published private(set) var records: [RunRecord] = []
    @Published private(set) var settings = RunSettings()
    @Published var errorMessage: String?
    @Published private(set) var storageAvailable = true
    @Published private(set) var syncState = RunSyncState(records: [])
    @Published private(set) var isSyncing = false
    @Published private(set) var syncMessage = "未开启 iCloud 同步"
    @Published private(set) var syncFailed = false
    private let fileURL: URL
    private let cloud = CloudRunService()
    private var debounceTask: Task<Void, Never>?
    private var syncAgain = false

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
                syncState = archive.syncState ?? RunSyncState(records: records)
                if syncState.enabled { syncMessage = "等待同步" }
            }
        } catch {
            // 读取失败时锁定写入，防止空数组覆盖原始文件。
            storageAvailable = false
            errorMessage = "无法读取本地数据，已暂停写入以保护原文件。\n\(error.localizedDescription)"
        }
    }
    private func persist(state: RunSyncState, settings: RunSettings) throws {
        guard storageAvailable else { throw RunError.invalid("本地数据读取失败，请先保留应用数据并检查存储文件。") }
        let archive = RunArchive(records: state.records, settings: settings, syncState: state)
        try archive.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: fileURL, options: .atomic)
        records = state.records; self.settings = settings; syncState = state
    }
    func save(_ record: RunRecord) throws {
        try record.validate()
        var state = syncState; state.change(id: record.id, record: record)
        try persist(state: state, settings: settings); requestSync()
    }
    func delete(_ record: RunRecord) {
        do {
            var state = syncState; state.change(id: record.id, record: nil)
            try persist(state: state, settings: settings); requestSync()
        } catch { errorMessage = error.localizedDescription }
    }
    func updateSettings(_ settings: RunSettings) {
        do { try persist(state: syncState, settings: settings) }
        catch { errorMessage = error.localizedDescription }
    }
    /// 导入视为本机的新编辑，保留同步墓碑和账号绑定，不导入其他设备的账号信息。
    func importBackup(_ data: Data) throws -> Int {
        guard data.count <= 20_000_000 else { throw RunError.invalid("备份不能超过 20 MB。") }
        let archive = try JSONDecoder().decode(RunArchive.self, from: data)
        try archive.validate()
        var state = syncState
        for record in archive.records { state.change(id: record.id, record: record) }
        try persist(state: state, settings: settings); requestSync()
        return archive.records.count
    }
    func backup() throws -> Data {
        guard storageAvailable else { throw RunError.invalid("本地数据读取失败，暂时无法导出。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(RunArchive(records: records, settings: settings))
    }
    func setCloudEnabled(_ enabled: Bool) {
        guard !isSyncing else { return }
        do {
            var state = syncState; state.enabled = enabled
            try persist(state: state, settings: settings)
            syncFailed = false; syncMessage = enabled ? "等待同步" : "未开启 iCloud 同步"
            if enabled { requestSync() } else { debounceTask?.cancel() }
        } catch { errorMessage = error.localizedDescription }
    }
    /// 短时间内连续编辑只触发一轮请求；用户点击立即同步时无需等待防抖。
    private func requestSync() {
        guard syncState.enabled, storageAvailable else { return }
        if isSyncing { syncAgain = true; return }
        syncMessage = "有更改等待同步"
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await self?.syncNow()
        }
    }
    func syncNow() async {
        guard syncState.enabled, storageAvailable else { return }
        guard !isSyncing else { syncAgain = true; return }
        isSyncing = true; syncAgain = false; syncFailed = false; syncMessage = "正在同步…"
        defer {
            isSyncing = false
            if syncAgain { requestSync() }
        }
        do {
            for attempt in 0..<3 {
                do {
                    let snapshot = try await cloud.fetch(expectedAccountID: syncState.accountID)
                    try Task.checkCancellation()
                    guard syncState.enabled else { return }
                    // 等待网络期间仍允许记跑步，因此必须与此刻最新本机版本合并。
                    var merged = syncState
                    merged.entries = try RunSyncEntry.merge(syncState.entries, snapshot.entries)
                    merged.accountID = snapshot.accountID
                    try persist(state: merged, settings: settings)
                    let sent = merged.entries
                    try await cloud.upload(sent, snapshot: snapshot)
                    try Task.checkCancellation()
                    if syncState.entries != sent {
                        // 上传期间又有编辑，下一轮继续同步；不能把尚未上传的修改标记成功。
                        if attempt < 2 { continue }
                        syncAgain = true; syncMessage = "有新更改等待同步"; return
                    }
                    var completed = syncState; completed.lastSyncedAt = Date()
                    try persist(state: completed, settings: settings)
                    syncAgain = false; syncMessage = "已同步至 iCloud"; return
                } catch {
                    if CloudRunService.isConflict(error), attempt < 2 { continue }
                    throw error
                }
            }
        } catch is CancellationError {
            syncAgain = false; syncMessage = "同步已暂停，本地记录已保留"
        } catch {
            // 自动同步失败只更新状态，不反复弹窗打断用户；前台轮询或手动重试会继续同步。
            syncAgain = false; syncFailed = true; syncMessage = CloudRunService.message(for: error)
        }
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
