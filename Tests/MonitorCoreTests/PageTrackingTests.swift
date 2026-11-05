import XCTest
import CSQLite
@testable import MonitorCore

final class PageTrackingTests: XCTestCase {
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    func testOldPayloadAndValidatedPageMetadata() throws {
        let old = try JSONDecoder().decode(BrowserUpdate.self, from: Data(#"{"domain":"example.com","focused":true}"#.utf8))
        XCTAssertTrue(old.isValid)
        XCTAssertNil(old.url)
        XCTAssertTrue(BrowserUpdate(domain: "example.com", focused: true,
            url: "https://example.com/path?q=hello#route", title: "页面标题 👩‍💻").isValid)
        for url in ["https://other.com/a", "file:///a", "javascript:alert(1)", "https://user:password@example.com/a", "https://example.com/a\n"] {
            XCTAssertFalse(BrowserUpdate(domain: "example.com", focused: true, url: url).isValid, url)
        }
        XCTAssertFalse(BrowserUpdate(domain: nil, focused: false, url: "https://example.com").isValid)
        XCTAssertFalse(BrowserUpdate(domain: "example.com", focused: true, title: "title without URL").isValid)
        XCTAssertFalse(BrowserUpdate(domain: "example.com", focused: true, url: "https://example.com/", title: String(repeating: "中", count: 342)).isValid)
    }

    func testPageSwitchesSplitSameDomainWhileTitleUpdatesMergeAndTotalsStaySeparate() throws {
        let store = try ActivityStore(path: ":memory:")
        var tracker = ActivityTracker(now: date(0))
        tracker.setApplication(ActivityIdentity(key: ActivityTracker.chromeBundleID, name: "Chrome"))
        tracker.setBrowser(BrowserUpdate(domain: "example.com", focused: true, url: "https://example.com/one", title: "Loading"), at: date(0))
        try store.record(tracker.advance(to: date(5)))
        tracker.setBrowser(BrowserUpdate(domain: "example.com", focused: true, url: "https://example.com/one", title: "First page"), at: date(5))
        try store.record(tracker.advance(to: date(10)))
        tracker.setBrowser(BrowserUpdate(domain: "example.com", focused: true, url: "https://example.com/two", title: "Second page"), at: date(10))
        try store.record(tracker.advance(to: date(15)))
        tracker.setBrowser(BrowserUpdate(domain: "example.com", focused: true, url: "https://example.com/one", title: "First page"), at: date(15))
        try store.record(tracker.advance(to: date(20)))
        let visits = try store.sessions(kind: .website, key: "example.com", from: date(0), to: date(30))
        XCTAssertEqual(visits.count, 3)
        XCTAssertEqual(visits.map(\.seconds), [10, 5, 5])
        XCTAssertEqual(visits.map(\.pageTitle), ["First page", "Second page", "First page"])
        XCTAssertEqual(try store.summaries(kind: .application, from: date(0), to: date(30)).first?.seconds, 20)
        XCTAssertEqual(try store.summaries(kind: .website, from: date(0), to: date(30)).first?.seconds, 20)
        let clipped = try store.activities(from: date(3), to: date(7)).first { $0.kind == .website }
        XCTAssertEqual(clipped?.seconds, 4)
        XCTAssertEqual(clipped?.pageURL, "https://example.com/one")
        let exported = try JSONEncoder().encode(visits)
        XCTAssertEqual(try JSONDecoder().decode([ActivitySlice].self, from: exported)[1].pageTitle, "Second page")
    }

    func testLegacyDatabaseMigratesAndReopensWithoutChangingHistory() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE activities (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, activity_key TEXT NOT NULL, name TEXT NOT NULL, started REAL NOT NULL, ended REAL NOT NULL); INSERT INTO activities VALUES (1, 'website', 'example.com', 'example.com', 0, 10);", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        do {
            let store = try ActivityStore(path: path)
            try store.record([ActivitySlice(kind: .website, key: "example.com", name: "example.com", start: date(10), end: date(20),
                pageURL: "https://example.com/a?q='quoted'", pageTitle: "页面 ' title")])
        }
        let store = try ActivityStore(path: path)
        let rows = try store.sessions(kind: .website, key: "example.com", from: date(0), to: date(30))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.id, 1)
        XCTAssertNil(rows.first?.pageURL)
        XCTAssertEqual(rows.last?.pageTitle, "页面 ' title")
        XCTAssertEqual(rows.map(\.seconds), [10, 10])
        try store.deleteAll()
        XCTAssertTrue(try store.activities(from: date(0), to: date(30)).isEmpty)
    }
}
