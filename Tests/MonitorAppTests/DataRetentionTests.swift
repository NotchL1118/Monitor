import XCTest
import MonitorCore
@testable import Monitor

final class DataRetentionTests: XCTestCase {
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    func testCutoffAlignsToReportDayAndForeverKeepsEverything() {
        let calendar = ReportTimeZone.utcPlus8.calendar
        let now = date("2026-11-05T10:00:00Z") // 18:00 on 5 Nov in UTC+8.
        XCTAssertNil(DataRetention.forever.cutoff(now: now, calendar: calendar))
        XCTAssertEqual(DataRetention.oneMonth.cutoff(now: now, calendar: calendar), date("2026-10-04T16:00:00Z"))
        XCTAssertEqual(DataRetention.oneYear.cutoff(now: now, calendar: calendar), date("2025-11-04T16:00:00Z"))
        // Month arithmetic clamps at short months.
        XCTAssertEqual(DataRetention.oneMonth.cutoff(now: date("2026-03-31T04:00:00Z"), calendar: calendar),
                       date("2026-02-27T16:00:00Z"))
    }

    @MainActor
    func testPreferencePersistsAndRetentionPrunesOldRecords() throws {
        let name = "Monitor-Retention-QA-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let store = try ActivityStore(path: directory.appendingPathComponent("activity.sqlite").path)
            let old = Date().addingTimeInterval(-200 * 86400), recent = Date().addingTimeInterval(-3600)
            try store.record([
                ActivitySlice(kind: .application, key: "old", name: "Old", start: old, end: old.addingTimeInterval(60)),
                ActivitySlice(kind: .application, key: "recent", name: "Recent", start: recent, end: recent.addingTimeInterval(60)),
            ])
        }
        let model = MonitorModel(dataDirectory: directory, preferences: preferences)
        XCTAssertEqual(model.dataRetention, .forever)
        try model.openStorage()
        XCTAssertNil(model.pendingDeletion(for: .oneYear))
        XCTAssertEqual(model.pendingDeletion(for: .threeMonths)?.count, 1)
        model.refreshStorageUsage()
        XCTAssertGreaterThan(model.storageUsage?.bytes ?? 0, 0)
        model.setDataRetention(.threeMonths)
        XCTAssertEqual(model.notice, "已删除 1 条超出保留期限的记录。")
        XCTAssertNil(model.pendingDeletion(for: .oneMonth))
        let earliest = try XCTUnwrap(model.storageUsage?.earliest)
        XCTAssertGreaterThan(earliest, Date().addingTimeInterval(-86400))
        XCTAssertEqual(MonitorModel(preferences: preferences).dataRetention, .threeMonths)
        preferences.set("bogus", forKey: DataRetention.preferenceKey)
        XCTAssertEqual(MonitorModel(preferences: preferences).dataRetention, .forever)
    }
}
