import XCTest
@testable import MonitorCore

final class StoreTests: XCTestCase {
    private func slice(_ start: Double, _ end: Double, key: String = "app", kind: ActivityKind = .application) -> ActivitySlice {
        ActivitySlice(kind: kind, key: key, name: key, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    func testContiguousSessionsMergeButGapsAndSwitchesRemain() throws {
        let store = try ActivityStore(path: ":memory:")
        try store.record([slice(0, 5), slice(5, 10), slice(12, 15), slice(15, 20, key: "other"), slice(20, 25)])
        let rows = try store.activities(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(rows.count, 4)
        let totals = try store.summaries(kind: .application, from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(totals[0].seconds, 18)
        XCTAssertEqual(totals[1].seconds, 5)
    }

    func testDayBoundaryClipsRatherThanDoubleCounting() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertEqual(end.timeIntervalSince(start), 25 * 3600) // DST fall-back day.
        let store = try ActivityStore(path: ":memory:")
        try store.record([ActivitySlice(kind: .application, key: "app", name: "App",
            start: start.addingTimeInterval(-30), end: start.addingTimeInterval(90))])
        let today = try store.summaries(kind: .application, from: start, to: end)
        let yesterday = try store.summaries(kind: .application, from: start.addingTimeInterval(-86400), to: start)
        XCTAssertEqual(today.first?.seconds, 90)
        XCTAssertEqual(yesterday.first?.seconds, 30)
        XCTAssertEqual(try store.activities(from: start, to: end).first?.start, start)
    }

    func testWebsiteTotalsAreSeparateAndExportPreservesKinds() throws {
        let store = try ActivityStore(path: ":memory:")
        try store.record([slice(0, 10), slice(0, 10, key: "example.com", kind: .website)])
        let start = Date(timeIntervalSince1970: 0), end = Date(timeIntervalSince1970: 20)
        XCTAssertEqual(try store.summaries(kind: .application, from: start, to: end).first?.seconds, 10)
        XCTAssertEqual(try store.summaries(kind: .website, from: start, to: end).first?.seconds, 10)
        XCTAssertEqual(try store.activities(from: start, to: end, limit: -1).count, 2)
    }

    func testDatabasePersistsAndNamesAreBoundAsData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.sqlite").path
        let name = "Editor'); DROP TABLE activities;--"
        do { let store = try ActivityStore(path: path); try store.record([slice(0, 10, key: name)]) }
        let reopened = try ActivityStore(path: path)
        let rows = try reopened.summaries(kind: .application, from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(rows.first?.name, name)
        XCTAssertEqual(rows.first?.seconds, 10)
        try reopened.deleteAll()
        XCTAssertTrue(try reopened.activities(from: .distantPast, to: .distantFuture).isEmpty)
    }

    func testApplicationDetailsIncludeFullRangeAndOnlySelectedIdentity() throws {
        let store = try ActivityStore(path: ":memory:")
        let key = "app' quoted"
        var slices = (0..<260).map { slice(Double($0 * 20), Double($0 * 20 + 10), key: key) }
        slices.append(slice(5, 45, key: key, kind: .website))
        slices.append(slice(5, 45, key: "other"))
        try store.record(slices)
        let start = Date(timeIntervalSince1970: 3), end = Date(timeIntervalSince1970: 5187)
        let sessions = try store.sessions(kind: .application, key: key, from: start, to: end)
        XCTAssertEqual(sessions.count, 260)
        XCTAssertEqual(sessions.first?.start, start)
        XCTAssertEqual(sessions.last?.end, end)
        XCTAssertEqual(sessions.reduce(0) { $0 + $1.seconds }, 2594)
        let summary = try store.summaries(kind: .application, from: start, to: end).first { $0.key == key }
        XCTAssertEqual(summary?.seconds, sessions.reduce(0) { $0 + $1.seconds })
        XCTAssertTrue(try store.sessions(kind: .application, key: "missing", from: start, to: end).isEmpty)
    }
}
