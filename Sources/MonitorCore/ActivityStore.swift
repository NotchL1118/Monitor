import Foundation
import CSQLite

public struct StoreError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Accessed on one serial executor; SQLite WAL also permits external read-only inspection.
public final class ActivityStore {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close(db); db = nil
            throw StoreError(message: message)
        }
        do {
            sqlite3_busy_timeout(db, 2000)
            try execute("PRAGMA journal_mode=WAL;")
            // Truncate the WAL back to 1 MB after each checkpoint instead of leaving it at its high-water mark.
            try execute("PRAGMA journal_size_limit=1048576;")
            try execute("CREATE TABLE IF NOT EXISTS activities (id INTEGER PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('application','website')), activity_key TEXT NOT NULL, name TEXT NOT NULL, started REAL NOT NULL, ended REAL NOT NULL CHECK(ended >= started));")
            // Add nullable columns in one transaction; domain-only history stays intact.
            let columns = try prepare("PRAGMA table_info(activities);")
            var names: Set<String> = []
            while sqlite3_step(columns) == SQLITE_ROW { names.insert(string(columns, 1)) }
            sqlite3_finalize(columns)
            try execute("BEGIN IMMEDIATE;")
            do {
                if !names.contains("page_url") { try execute("ALTER TABLE activities ADD COLUMN page_url TEXT;") }
                if !names.contains("page_title") { try execute("ALTER TABLE activities ADD COLUMN page_title TEXT;") }
                try execute("COMMIT;")
            } catch { try? execute("ROLLBACK;"); throw error }
            try execute("CREATE INDEX IF NOT EXISTS activities_period ON activities(kind, ended, started);")
        } catch { sqlite3_close(db); db = nil; throw error }
    }

    deinit { sqlite3_close(db) }

    private func fail() -> StoreError { StoreError(message: String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw fail() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw fail() }
        return statement
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }
    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private func optionalString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : string(statement, index)
    }
    private func bindOptional(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        if let value { bind(value, to: statement, at: index) }
        else { sqlite3_bind_null(statement, index) }
    }

    public func record(_ slices: [ActivitySlice]) throws {
        guard !slices.isEmpty else { return }
        try execute("BEGIN IMMEDIATE;")
        do {
            for slice in slices where slice.end > slice.start { try append(slice) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    private func append(_ slice: ActivitySlice) throws {
        let previous = try prepare("SELECT id, activity_key, ended, page_url FROM activities WHERE kind = ? ORDER BY id DESC LIMIT 1;")
        defer { sqlite3_finalize(previous) }
        bind(slice.kind.rawValue, to: previous, at: 1)
        let result = sqlite3_step(previous)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw fail() }
        let merges = result == SQLITE_ROW && string(previous, 1) == slice.key && optionalString(previous, 3) == slice.pageURL &&
            abs(sqlite3_column_double(previous, 2) - slice.start.timeIntervalSince1970) < 0.001
        if merges {
            let statement = try prepare("UPDATE activities SET ended = ?, name = ?, page_title = COALESCE(?, page_title) WHERE id = ?;")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, slice.end.timeIntervalSince1970)
            bind(slice.name, to: statement, at: 2)
            bindOptional(slice.pageTitle, to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, sqlite3_column_int64(previous, 0))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw fail() }
        } else {
            let statement = try prepare("INSERT INTO activities(kind, activity_key, name, started, ended, page_url, page_title) VALUES (?, ?, ?, ?, ?, ?, ?);")
            defer { sqlite3_finalize(statement) }
            bind(slice.kind.rawValue, to: statement, at: 1)
            bind(slice.key, to: statement, at: 2)
            bind(slice.name, to: statement, at: 3)
            sqlite3_bind_double(statement, 4, slice.start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 5, slice.end.timeIntervalSince1970)
            bindOptional(slice.pageURL, to: statement, at: 6)
            bindOptional(slice.pageTitle, to: statement, at: 7)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw fail() }
        }
    }

    public func summaries(kind: ActivityKind, from start: Date, to end: Date) throws -> [UsageSummary] {
        let statement = try prepare("SELECT activity_key, MAX(name), SUM(MIN(ended, ?)-MAX(started, ?)) AS seconds FROM activities WHERE kind = ? AND ended > ? AND started < ? GROUP BY activity_key ORDER BY seconds DESC;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, end.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, start.timeIntervalSince1970)
        bind(kind.rawValue, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, end.timeIntervalSince1970)
        var rows: [UsageSummary] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw fail() }
            rows.append(UsageSummary(key: string(statement, 0), name: string(statement, 1), seconds: sqlite3_column_double(statement, 2)))
        }
        return rows
    }

    public func activities(from start: Date, to end: Date, limit: Int = 200) throws -> [ActivitySlice] {
        let statement = try prepare("SELECT id, kind, activity_key, name, MAX(started, ?), MIN(ended, ?), page_url, page_title FROM activities WHERE ended > ? AND started < ? ORDER BY started DESC LIMIT ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, end.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 5, Int64(limit))
        var rows: [ActivitySlice] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw fail() }
            guard let kind = ActivityKind(rawValue: string(statement, 1)) else { continue }
            rows.append(ActivitySlice(id: sqlite3_column_int64(statement, 0), kind: kind,
                key: string(statement, 2), name: string(statement, 3),
                start: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                end: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                pageURL: optionalString(statement, 6), pageTitle: optionalString(statement, 7)))
        }
        return rows
    }

    /// Full history for a kind or one identity within the report, independent of the overview's 200-row limit.
    public func sessions(kind: ActivityKind, key: String? = nil, from start: Date, to end: Date) throws -> [ActivitySlice] {
        let identityFilter = key == nil ? "" : " AND activity_key = ?"
        let statement = try prepare("SELECT id, activity_key, name, MAX(started, ?), MIN(ended, ?), page_url, page_title FROM activities WHERE kind = ? AND ended > ? AND started < ?\(identityFilter) ORDER BY started, id;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        bind(kind.rawValue, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, end.timeIntervalSince1970)
        if let key { bind(key, to: statement, at: 6) }
        var rows: [ActivitySlice] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw fail() }
            rows.append(ActivitySlice(id: sqlite3_column_int64(statement, 0), kind: kind, key: string(statement, 1),
                name: string(statement, 2), start: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                end: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                pageURL: optionalString(statement, 5), pageTitle: optionalString(statement, 6)))
        }
        return rows
    }

    /// Start of the oldest stored slice, or nil when the store is empty.
    public func earliestActivityStart() throws -> Date? {
        let statement = try prepare("SELECT MIN(started) FROM activities;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw fail() }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
    }

    /// Number of slices that `deleteActivities(endedBefore:)` would remove.
    public func activityCount(endedBefore cutoff: Date) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM activities WHERE ended <= ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw fail() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Removes slices that ended at or before `cutoff` and compacts the file.
    /// Slices that cross the cutoff stay whole, so no raw slice is ever rewritten.
    @discardableResult
    public func deleteActivities(endedBefore cutoff: Date) throws -> Int {
        let statement = try prepare("DELETE FROM activities WHERE ended <= ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw fail() }
        let deleted = Int(sqlite3_changes(db))
        if deleted > 0 {
            try execute("VACUUM;")
            try execute("PRAGMA wal_checkpoint(TRUNCATE);")
        }
        return deleted
    }

    public func deleteAll() throws {
        try execute("PRAGMA secure_delete=ON;")
        try execute("DELETE FROM activities;")
        try execute("VACUUM;")
        try execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }
}
