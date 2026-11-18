//
//  SQLiteDatabase.swift
//  Memora
//
//  A thin, safe Swift wrapper over the SQLite3 C API.
//
//  Rationale: Memora must manage tens of thousands of cards with Anki-style
//  scheduling queries. Raw SQLite with hand-tuned indices and prepared
//  statements gives predictable performance and full control over the schema,
//  which SwiftData / Core Data do not at this scale. This wrapper keeps the
//  rest of the app free of C-interop details while exposing prepared
//  statements, transactions and streaming row iteration.
//
//  No networking, telemetry or external services are used anywhere.
//

import Foundation
import SQLite3

/// `SQLITE_TRANSIENT` tells SQLite to copy bound bytes before returning.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Errors thrown by the SQLite layer.
public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public let context: String

    public var description: String {
        "SQLiteError(code: \(code), context: \(context), message: \(message))"
    }
}

/// A value that can be bound to a SQLite statement parameter.
public enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

/// A lightweight, non-escaping wrapper around a prepared statement row,
/// used while iterating results. Column access is 0-based.
public struct SQLiteRow {
    fileprivate let stmt: OpaquePointer

    public func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
    }

    public func int(_ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    public func intOptional(_ index: Int32) -> Int64? {
        isNull(index) ? nil : sqlite3_column_int64(stmt, index)
    }

    public func double(_ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    public func doubleOptional(_ index: Int32) -> Double? {
        isNull(index) ? nil : sqlite3_column_double(stmt, index)
    }

    public func string(_ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    public func stringOptional(_ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    public func blob(_ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }

    public func blobOptional(_ index: Int32) -> Data? {
        isNull(index) ? nil : blob(index)
    }
}

/// A prepared statement. Not thread-safe; use within a single `SQLiteDatabase`
/// queue context.
public final class SQLiteStatement {
    fileprivate let stmt: OpaquePointer
    private unowned let db: SQLiteDatabase

    fileprivate init(stmt: OpaquePointer, db: SQLiteDatabase) {
        self.stmt = stmt
        self.db = db
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    /// Reset so the statement can be re-executed with new bindings.
    @discardableResult
    public func reset() -> SQLiteStatement {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        return self
    }

    public func bind(_ values: [SQLiteValue]) throws {
        for (i, value) in values.enumerated() {
            try bind(value, at: Int32(i + 1))
        }
    }

    public func bind(_ value: SQLiteValue, at index: Int32) throws {
        let rc: Int32
        switch value {
        case .null:
            rc = sqlite3_bind_null(stmt, index)
        case .integer(let v):
            rc = sqlite3_bind_int64(stmt, index, v)
        case .real(let v):
            rc = sqlite3_bind_double(stmt, index, v)
        case .text(let v):
            rc = sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
        case .blob(let v):
            if v.isEmpty {
                rc = sqlite3_bind_zeroblob(stmt, index, 0)
            } else {
                rc = v.withUnsafeBytes {
                    sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
                }
            }
        }
        if rc != SQLITE_OK { throw db.lastError(context: "bind") }
    }

    /// Steps once. Returns true if a row is available, false when done.
    public func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw db.lastError(context: "step")
    }

    /// Iterate all rows, calling `body` for each. Automatically resets on exit.
    public func forEachRow(_ body: (SQLiteRow) throws -> Void) throws {
        defer { reset() }
        let row = SQLiteRow(stmt: stmt)
        while try step() {
            try body(row)
        }
    }

    /// Execute a statement expected to return no rows (INSERT/UPDATE/DELETE).
    public func run(_ values: [SQLiteValue] = []) throws {
        reset()
        try bind(values)
        _ = try step()
        reset()
    }
}

/// A SQLite database connection with transaction and migration helpers.
public final class SQLiteDatabase {
    fileprivate var handle: OpaquePointer?
    public let path: String

    /// Open (and create if needed) a database at `path`.
    /// Pass `":memory:"` for an in-memory database (used by tests).
    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        var flags = SQLITE_OPEN_FULLMUTEX
        flags |= readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, handle != nil else {
            let msg = handle != nil ? String(cString: sqlite3_errmsg(handle)) : "unable to open"
            if handle != nil { sqlite3_close_v2(handle) }
            throw SQLiteError(code: rc, message: msg, context: "open")
        }
        // Reasonable defaults for a local, single-process app database.
        sqlite3_busy_timeout(handle, 5_000)
        if !readOnly {
            try? exec("PRAGMA journal_mode=WAL;")
            try? exec("PRAGMA synchronous=NORMAL;")
            try? exec("PRAGMA foreign_keys=ON;")
            try? exec("PRAGMA temp_store=MEMORY;")
        }
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    fileprivate func lastError(context: String) -> SQLiteError {
        let code = sqlite3_errcode(handle)
        let msg = String(cString: sqlite3_errmsg(handle))
        return SQLiteError(code: code, message: msg, context: context)
    }

    /// Execute one or more statements with no result handling.
    public func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? "exec failed"
            if let errMsg { sqlite3_free(errMsg) }
            throw SQLiteError(code: rc, message: message, context: "exec")
        }
    }

    /// Prepare a reusable statement.
    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw lastError(context: "prepare: \(sql)") }
        return SQLiteStatement(stmt: stmt, db: self)
    }

    /// Convenience: run a write statement once.
    public func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let stmt = try prepare(sql)
        try stmt.run(values)
    }

    /// Convenience: query rows, mapping each with `transform`.
    public func query<T>(_ sql: String, _ values: [SQLiteValue] = [], _ transform: (SQLiteRow) throws -> T) throws -> [T] {
        let stmt = try prepare(sql)
        try stmt.bind(values)
        var result: [T] = []
        try stmt.forEachRow { row in result.append(try transform(row)) }
        return result
    }

    /// Convenience: scalar integer (e.g. COUNT).
    public func scalarInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int64 {
        let stmt = try prepare(sql)
        try stmt.bind(values)
        var value: Int64 = 0
        if try stmt.step() { value = sqlite3_column_int64(stmt.stmt, 0) }
        stmt.reset()
        return value
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    public var changes: Int32 { sqlite3_changes(handle) }

    private var transactionDepth = 0

    /// Run `body` inside a transaction. Rolls back on any thrown error so a
    /// failed import can never leave the database half-written. Reentrant:
    /// nested calls use SAVEPOINTs, so high-level store methods that each open
    /// a transaction can be composed inside a larger import transaction.
    ///
    /// Not safe for concurrent writers on different threads; Memora serialises
    /// writes (imports run on a single background queue).
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        let depth = transactionDepth
        if depth == 0 {
            try exec("BEGIN IMMEDIATE;")
        } else {
            try exec("SAVEPOINT memora_sp\(depth);")
        }
        transactionDepth = depth + 1
        do {
            let result = try body()
            transactionDepth = depth
            if depth == 0 {
                try exec("COMMIT;")
            } else {
                try exec("RELEASE memora_sp\(depth);")
            }
            return result
        } catch {
            transactionDepth = depth
            if depth == 0 {
                try? exec("ROLLBACK;")
            } else {
                try? exec("ROLLBACK TO memora_sp\(depth);")
                try? exec("RELEASE memora_sp\(depth);")
            }
            throw error
        }
    }

    /// Run a VACUUM to reclaim space (used after large deletions / restore).
    public func vacuum() throws { try exec("VACUUM;") }

    /// Integrity check — returns "ok" when the database is healthy.
    public func integrityCheck() throws -> String {
        let rows = try query("PRAGMA integrity_check;") { $0.string(0) }
        return rows.first ?? "unknown"
    }

    /// Back up this database to another file using the SQLite online backup API.
    /// Safe to call while the database is in use.
    public func backup(to destinationPath: String) throws {
        let dest = try SQLiteDatabase(path: destinationPath)
        guard let backup = sqlite3_backup_init(dest.handle, "main", handle, "main") else {
            throw dest.lastError(context: "backup_init")
        }
        sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        let rc = sqlite3_errcode(dest.handle)
        if rc != SQLITE_OK && rc != SQLITE_DONE {
            throw dest.lastError(context: "backup")
        }
    }
}
