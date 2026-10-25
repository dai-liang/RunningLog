import XCTest
@testable import RunCore

final class RunCoreTests: XCTestCase {
    // 固定时区和时间，避免测试随运行日期或开发机器地区变化。
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }
    func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text + "+08:00")!
    }
    func testQuarterAndExclusiveEnd() {
        let anchor = date("2026-05-15T12:00:00")
        let interval = RunPeriod.quarter.interval(containing: anchor, calendar: calendar)
        XCTAssertEqual(interval.start, date("2026-04-01T00:00:00"))
        XCTAssertEqual(interval.end, date("2026-07-01T00:00:00"))
        let records = [
            RunRecord(date: interval.start, duration: 1800, distance: 5),
            RunRecord(date: interval.end, duration: 3600, distance: 10)
        ]
        let summary = RunSummary(records: records, interval: interval)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.duration, 1800)
        XCTAssertEqual(summary.distance, 5)
    }
    func testWeekStartsMondayAndCrossesYear() {
        let interval = RunPeriod.week.interval(containing: date("2026-01-01T12:00:00"), calendar: calendar)
        XCTAssertEqual(interval.start, date("2025-12-29T00:00:00"))
        XCTAssertEqual(interval.end, date("2026-01-05T00:00:00"))
    }
    func testLeapMonthBucketsAndWeightedPace() {
        let anchor = date("2024-02-20T12:00:00")
        XCTAssertEqual(RunPeriod.month.buckets(containing: anchor, calendar: calendar).count, 29)
        let records = [RunRecord(date: anchor, duration: 1200, distance: 5), RunRecord(date: anchor, duration: 3600, distance: 10)]
        let summary = RunSummary(records: records, interval: RunPeriod.month.interval(containing: anchor, calendar: calendar))
        XCTAssertEqual(summary.pace!, 320, accuracy: 0.01)
    }
    func testInvalidRecordsRejected() {
        let now = date("2026-10-25T12:00:00")
        XCTAssertThrowsError(try RunRecord(date: now, duration: 0, distance: 5).validate(now: now))
        XCTAssertThrowsError(try RunRecord(date: now, duration: 1, distance: -.infinity).validate(now: now))
        XCTAssertThrowsError(try RunRecord(date: now.addingTimeInterval(100), duration: 10, distance: 1).validate(now: now))
        XCTAssertNoThrow(try RunRecord(date: now, duration: 60, distance: 0).validate(now: now))
        XCTAssertThrowsError(try RunRecord(date: Date(timeIntervalSince1970: -1e100), duration: 60, distance: 1).validate(now: now))
        XCTAssertThrowsError(try RunRecord(date: now, duration: 0.1, distance: 1).validate(now: now))
    }
    func testArchiveRoundTripAndDuplicateRejection() throws {
        let record = RunRecord(date: Date().addingTimeInterval(-60), duration: 1800, distance: 5)
        let archive = RunArchive(records: [record], settings: RunSettings())
        let restored = try JSONDecoder().decode(RunArchive.self, from: JSONEncoder().encode(archive))
        try restored.validate()
        XCTAssertEqual(restored.records, [record])
        XCTAssertThrowsError(try RunArchive(records: [record, record], settings: RunSettings()).validate())
    }
    func testStreakAllowsCurrentWeekWithoutRun() {
        let now = date("2026-10-21T12:00:00")
        let records = [RunRecord(date: date("2026-10-14T12:00:00"), duration: 60, distance: 1), RunRecord(date: date("2026-10-07T12:00:00"), duration: 60, distance: 1)]
        XCTAssertEqual(RunStatistics.weekStreak(records: records, now: now, calendar: calendar), 2)
    }
    func testSundayWeekAndQuarterNavigation() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let anchor = date("2026-10-25T12:00:00")
        XCTAssertEqual(RunPeriod.week.interval(containing: anchor, calendar: sunday).start, date("2026-10-25T00:00:00"))
        XCTAssertEqual(RunPeriod.quarter.shifted(anchor, by: 1, calendar: calendar), date("2027-01-01T00:00:00"))
        XCTAssertEqual(RunPeriod.year.buckets(containing: anchor, calendar: calendar).count, 12)
    }
    func testMissingDistanceExcludedFromPaceButIncludedInDuration() {
        let now = date("2026-10-25T12:00:00")
        let records = [RunRecord(date: now, duration: 1800, distance: 5), RunRecord(date: now, duration: 600, distance: 0)]
        let summary = RunSummary(records: records, interval: RunPeriod.year.interval(containing: now, calendar: calendar))
        XCTAssertEqual(summary.duration, 2400)
        XCTAssertEqual(summary.pace, 360)
        XCTAssertEqual(summary.count, 2)
        XCTAssertNil(RunSummary(records: [], interval: RunPeriod.year.interval(containing: now, calendar: calendar)).pace)
    }
    func testUnsupportedArchiveAndInvalidSettingsRejected() {
        var archive = RunArchive(records: [], settings: RunSettings())
        archive.version = 2
        XCTAssertThrowsError(try archive.validate())
        archive.version = 1
        archive.settings.weeklyCount = 0
        XCTAssertThrowsError(try archive.validate())
    }

}
