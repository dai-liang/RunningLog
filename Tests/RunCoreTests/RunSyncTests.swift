import XCTest
@testable import RunCore

/// 同步依赖可重复的合并规则，测试无需登录真实 iCloud，也不会上传测试数据。
final class RunSyncTests: XCTestCase {
    let first = Date(timeIntervalSince1970: 1_700_000_000)
    func entry(id: UUID, seconds: Double, note: String = "", deleted: Bool = false, revision: String = "A") -> RunSyncEntry {
        RunSyncEntry(id: id, record: deleted ? nil : RunRecord(id: id, date: first, duration: 60, note: note),
                     modifiedAt: first.addingTimeInterval(seconds), revision: revision)
    }
    func testIndependentDevicesKeepBothRecords() throws {
        let a = entry(id: UUID(), seconds: 0), b = entry(id: UUID(), seconds: 1)
        let result = try RunSyncEntry.merge([a], [b])
        XCTAssertEqual(Set(result.map(\.id)), [a.id, b.id])
    }
    func testNewerEditWinsInEitherMergeOrder() throws {
        let id = UUID(), a = entry(id: UUID(), seconds: 0)
        let old = entry(id: id, seconds: 1, note: "旧备注")
        let new = entry(id: id, seconds: 2, note: "新备注")
        XCTAssertEqual(try RunSyncEntry.merge([a, old], [new]), try RunSyncEntry.merge([new], [old, a]))
        XCTAssertEqual(try RunSyncEntry.merge([old], [new]).first?.record?.note, "新备注")
    }
    func testDeletionDoesNotResurrectFromOfflineDevice() throws {
        let id = UUID(), old = entry(id: id, seconds: 0)
        let deletion = entry(id: id, seconds: 2, deleted: true)
        XCTAssertNil(try RunSyncEntry.merge([old], [deletion]).first?.record)
        XCTAssertNil(try RunSyncEntry.merge([deletion], [old]).first?.record)
    }
    func testTieBreakIsDeterministicAndMergeIsIdempotent() throws {
        let id = UUID(), a = entry(id: id, seconds: 1, note: "甲", revision: "A")
        let b = entry(id: id, seconds: 1, note: "乙", revision: "B")
        let merged = try RunSyncEntry.merge([a], [b])
        XCTAssertEqual(merged.first?.record?.note, "乙")
        XCTAssertEqual(merged, try RunSyncEntry.merge(merged, merged))
        XCTAssertEqual(merged, try RunSyncEntry.merge([b], [a]))
    }
    func testCorruptRemoteDataAbortsWholeMerge() {
        let id = UUID()
        let malformed = RunSyncEntry(id: id, record: RunRecord(), modifiedAt: first, revision: "A")
        XCTAssertThrowsError(try RunSyncEntry.merge([entry(id: UUID(), seconds: 0)], [malformed]))
        let a = entry(id: id, seconds: 0)
        XCTAssertThrowsError(try RunSyncEntry.merge([], [a, a]))
    }
    func testLegacyArchiveDecodesAndMigratesWithoutChangingRecords() throws {
        let record = RunRecord(date: first, duration: 1800, distance: 5)
        let old = RunArchive(records: [record], settings: RunSettings())
        let data = try JSONEncoder().encode(old)
        let restored = try JSONDecoder().decode(RunArchive.self, from: data)
        XCTAssertNil(restored.syncState)
        let state = RunSyncState(records: restored.records)
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.records, [record])
        try state.validate(records: restored.records)
    }
    func testSyncStateRoundTripPreservesDeletionAndAccountBinding() throws {
        let id = UUID()
        var state = RunSyncState(records: [])
        state.entries = [entry(id: id, seconds: 1, deleted: true)]
        state.enabled = true; state.accountID = "测试账号"
        let archive = RunArchive(records: [], settings: RunSettings(), syncState: state)
        let restored = try JSONDecoder().decode(RunArchive.self, from: JSONEncoder().encode(archive))
        try restored.validate()
        XCTAssertEqual(restored.syncState, state)
    }
    func testArchiveRejectsInconsistentVisibleRecords() {
        var state = RunSyncState(records: [])
        state.entries = [entry(id: UUID(), seconds: 0)]
        XCTAssertThrowsError(try state.validate(records: []))
    }
    func testRevisionCollisionWithDifferentDataIsRejected() {
        let id = UUID()
        XCTAssertThrowsError(try RunSyncEntry.merge([entry(id: id, seconds: 0, note: "甲")],
                                                   [entry(id: id, seconds: 0, note: "乙")]))
    }
    func testLocalDeletionAndClockRollbackRemainNewer() throws {
        let record = RunRecord(date: first, duration: 60)
        var state = RunSyncState(records: [record])
        state.change(id: record.id, record: record, now: first)
        let old = try XCTUnwrap(state.entries.first)
        state.change(id: record.id, record: nil, now: first.addingTimeInterval(-3600))
        XCTAssertTrue(try XCTUnwrap(state.entries.first).isNewer(than: old))
        XCTAssertTrue(state.records.isEmpty)
        try state.validate(records: [])
    }
    func testMergeAssociativityAcrossThreeDevices() throws {
        let id = UUID()
        let a = [entry(id: id, seconds: 0)]
        let b = [entry(id: id, seconds: 1, note: "较新"), entry(id: UUID(), seconds: 0)]
        let c = [entry(id: id, seconds: 2, deleted: true)]
        XCTAssertEqual(try RunSyncEntry.merge(RunSyncEntry.merge(a, b), c),
                       try RunSyncEntry.merge(a, RunSyncEntry.merge(b, c)))
    }

    func testMalformedMetadataRejected() {
        let id = UUID()
        let bad = RunSyncEntry(id: id, record: nil, modifiedAt: Date(timeIntervalSince1970: 1e100), revision: "A")
        XCTAssertThrowsError(try bad.validate())
        var state = RunSyncState(records: [])
        state.lastSyncedAt = Date(timeIntervalSince1970: 1e100)
        XCTAssertThrowsError(try state.validate(records: []))
        state.lastSyncedAt = nil; state.accountID = ""
        XCTAssertThrowsError(try state.validate(records: []))
    }

}
