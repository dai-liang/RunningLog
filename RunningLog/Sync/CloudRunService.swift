import CloudKit
import Foundation

/// CloudKit 访问集中在此处；只有用户开启同步且工程已配置签名后才创建容器。
@MainActor
final class CloudRunService {
    struct Snapshot {
        let accountID: String
        let entries: [RunSyncEntry]
        let serverRecords: [UUID: CKRecord]
        let database: CKDatabase
        let container: CKContainer
        let zoneID: CKRecordZone.ID
    }
    enum SyncFailure: LocalizedError {
        case setup, noAccount, restricted, unavailable, accountChanged, conflict
        var errorDescription: String? {
            switch self {
            case .setup: return "请先在 Xcode 配置开发者团队、iCloud / CloudKit 能力及容器，再使用已签名版本同步。"
            case .noAccount: return "请先在系统设置登录 iCloud，并允许本应用使用 iCloud。"
            case .restricted: return "当前 iCloud 账户受到系统限制，暂时不能同步。"
            case .unavailable: return "iCloud 暂时不可用，请稍后点击立即同步。"
            case .accountChanged: return "iCloud 账号与首次同步时不同，已暂停同步以避免混合账号数据。请切回原账号；迁移数据可使用 JSON 导出。"
            case .conflict: return "其他设备正在更新记录，请稍后重试同步。"
            }
        }
    }

    /// 每次重新读取当前账号。首次绑定后若账号切换，拒绝将本机记录传到另一个账号。
    func fetch(expectedAccountID: String?) async throws -> Snapshot {
        #if DEBUG
        // 界面测试只检查本地流程和配置提示，绝不向测试机登录的真实账号上传测试记录。
        if ProcessInfo.processInfo.environment["RUNNINGLOG_DISABLE_CLOUD_FOR_TESTS"] == "1" {
            throw SyncFailure.setup
        }
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        guard let team = info["RunningLogCloudSigningTeam"] as? String, !team.isEmpty,
              let allowed = info["RunningLogCloudSigningAllowed"] as? String, allowed == "YES",
              let identifier = info["RunningLogCloudContainer"] as? String, identifier.hasPrefix("iCloud.") else {
            throw SyncFailure.setup
        }
        let container = CKContainer(identifier: identifier)
        switch try await container.accountStatus() {
        case .available: break
        case .noAccount: throw SyncFailure.noAccount
        case .restricted: throw SyncFailure.restricted
        default: throw SyncFailure.unavailable
        }
        let owner = try await container.userRecordID().recordName
        if let expectedAccountID, owner != expectedAccountID { throw SyncFailure.accountChanged }
        try Task.checkCancellation()
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "RunningLogRecords", ownerName: CKCurrentUserDefaultName)
        do { _ = try await database.recordZone(for: zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }

        // 从空令牌读取整个自定义区域，不依赖查询索引；分页读完后才对外发布完整快照。
        var token: CKServerChangeToken?
        var rawRecords: [UUID: CKRecord] = [:]
        var entries: [UUID: RunSyncEntry] = [:]
        repeat {
            try Task.checkCancellation()
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, resultsLimit: 200)
            for (_, result) in page.modificationResultsByID {
                let record = try result.get().record
                guard record.recordType == "RunEntryV1" else { continue }
                guard let data = record["payload"] as? Data, data.count <= 100_000 else {
                    throw RunError.invalid("iCloud 中的跑步记录格式无效，已停止同步。")
                }
                let entry = try JSONDecoder().decode(RunSyncEntry.self, from: data)
                try entry.validate()
                guard record.recordID.recordName == entry.id.uuidString else {
                    throw RunError.invalid("iCloud 记录编号与内容不一致。")
                }
                rawRecords[entry.id] = record; entries[entry.id] = entry
            }
            for deletion in page.deletions {
                if let id = UUID(uuidString: deletion.recordID.recordName) {
                    rawRecords[id] = nil; entries[id] = nil
                }
            }
            token = page.changeToken
            if !page.moreComing { break }
        } while true
        return Snapshot(accountID: owner, entries: Array(entries.values), serverRecords: rawRecords,
                        database: database, container: container, zoneID: zoneID)
    }

    /// 使用服务器版本标记进行条件写入。遇到并发修改时交给存储层重新读取、合并并重试。
    func upload(_ entries: [RunSyncEntry], snapshot: Snapshot) async throws {
        let remote = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        let changes = entries.filter { remote[$0.id] != $0 }
        for start in stride(from: 0, to: changes.count, by: 100) {
            try Task.checkCancellation()
            // 写入前再次核对账号，避免同步过程中切换账号导致上传到错误的私有空间。
            guard try await snapshot.container.userRecordID().recordName == snapshot.accountID else {
                throw SyncFailure.accountChanged
            }
            let batch = changes[start..<min(start + 100, changes.count)]
            let records = try batch.map { entry -> CKRecord in
                let id = CKRecord.ID(recordName: entry.id.uuidString, zoneID: snapshot.zoneID)
                let record = snapshot.serverRecords[entry.id] ?? CKRecord(recordType: "RunEntryV1", recordID: id)
                record["payload"] = try JSONEncoder().encode(entry) as CKRecordValue
                return record
            }
            let result = try await snapshot.database.modifyRecords(saving: records, deleting: [],
                                                                    savePolicy: .ifServerRecordUnchanged, atomically: false)
            var firstError: Error?
            for (_, saved) in result.saveResults {
                if case .failure(let error) = saved { firstError = firstError ?? error }
            }
            if let firstError { throw firstError }
        }
    }

    /// CloudKit 的批量错误可能嵌套单条冲突；仅冲突立即重试，网络及限流留待下一轮。
    static func isConflict(_ error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        if cloud.code == .serverRecordChanged { return true }
        return cloud.partialErrorsByItemID?.values.contains { isConflict($0) } ?? false
    }
    static func message(for error: Error) -> String {
        guard let cloud = error as? CKError else { return error.localizedDescription }
        switch cloud.code {
        case .networkUnavailable, .networkFailure: return "网络不可用，记录已保存在本机。联网后可点击立即同步，或重新打开应用重试。"
        case .quotaExceeded: return "iCloud 存储空间不足，记录已保存在本机。请清理空间后重试。"
        case .notAuthenticated: return SyncFailure.noAccount.localizedDescription
        case .badContainer, .missingEntitlement, .permissionFailure:
            return "iCloud 容器或签名权限尚未配置完成，请按项目内 ICLOUD_SETUP.md 检查。"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud 服务繁忙，记录已保存在本机，请稍后手动重试。"
        default: return "同步未完成，记录仍保存在本机。\(cloud.localizedDescription)"
        }
    }
}
