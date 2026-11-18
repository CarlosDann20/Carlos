//
//  MemoraStore.swift
//  Memora
//
//  The single entry point to the collection database. Owns the SQLite
//  connection and the media directory, provides bootstrap/defaults, and
//  vends domain operations (see MemoraStore+*.swift).
//
//  All data stays on-device: the database file and media live under the app's
//  Application Support directory. No network access occurs here or anywhere
//  in Memora.
//

import Foundation

public final class MemoraStore {
    public let db: SQLiteDatabase
    public let mediaDirectory: URL
    public let databaseURL: URL

    private var lastTimestampID: Int64 = 0
    private let idLock = NSLock()

    /// Open (creating if needed) the collection at `databaseURL`, with media
    /// stored under `mediaDirectory`.
    public init(databaseURL: URL, mediaDirectory: URL) throws {
        self.databaseURL = databaseURL
        self.mediaDirectory = mediaDirectory
        do {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            self.db = try SQLiteDatabase(path: databaseURL.path)
            try Schema.migrate(db)
            try bootstrapIfNeeded()
        } catch let e as SQLiteError {
            throw MemoraError.db("No se pudo abrir la base de datos.", underlying: e)
        }
    }

    /// Convenience for tests / fallback: a throwaway file-backed store in a
    /// fresh temp directory.
    public static func inMemory() throws -> MemoraStore {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("memora-tmp-\(UUID().uuidString)")
        return try MemoraStore(databaseURL: tmp.appendingPathComponent("collection.sqlite"),
                               mediaDirectory: tmp.appendingPathComponent("media"))
    }

    // MARK: - Unique id generation (epoch-ms, collision-free during bulk ops)

    public func nextID() -> Int64 {
        idLock.lock(); defer { idLock.unlock() }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let id = max(now, lastTimestampID + 1)
        lastTimestampID = id
        return id
    }

    func noteMaxID() throws -> Int64 { try db.scalarInt("SELECT COALESCE(MAX(id),0) FROM notes") }

    // MARK: - Bootstrap

    private func bootstrapIfNeeded() throws {
        let hasCollection = try db.scalarInt("SELECT COUNT(*) FROM collection") > 0
        guard !hasCollection else {
            // Keep the id generator ahead of any existing ids.
            let maxNote = try db.scalarInt("SELECT COALESCE(MAX(id),0) FROM notes")
            let maxCard = try db.scalarInt("SELECT COALESCE(MAX(id),0) FROM cards")
            let maxRev = try db.scalarInt("SELECT COALESCE(MAX(id),0) FROM revlog")
            lastTimestampID = max(max(maxNote, maxCard), maxRev)
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        try db.transaction {
            try db.run("INSERT INTO collection (id, crt, rollover_hour, schema_version) VALUES (1, ?, 4, ?)",
                       [.integer(now), .integer(Int64(Schema.currentVersion))])
            // Default deck config.
            let config = DeckConfig.makeDefault()
            try saveDeckConfig(config)
            // Default deck.
            try db.run("""
                INSERT INTO decks (id, name, parent_id, config_id, collapsed, filtered, created, modified)
                VALUES (1, 'Predeterminado', NULL, 1, 0, 0, ?, ?)
                """, [.integer(now), .integer(now)])
        }
    }

    // MARK: - Collection settings

    public func collectionSettings() throws -> CollectionSettings {
        let rows = try db.query("SELECT crt, rollover_hour, schema_version FROM collection WHERE id = 1") { row in
            CollectionSettings(creationEpoch: row.int(0), rolloverHour: Int(row.int(1)), schemaVersion: Int(row.int(2)))
        }
        return rows.first ?? .makeDefault()
    }

    public func updateCollectionSettings(_ s: CollectionSettings) throws {
        try db.run("UPDATE collection SET crt = ?, rollover_hour = ?, schema_version = ? WHERE id = 1",
                   [.integer(s.creationEpoch), .integer(Int64(s.rolloverHour)), .integer(Int64(s.schemaVersion))])
    }

    public func dayClock() throws -> DayClock {
        let s = try collectionSettings()
        return DayClock(creationEpoch: s.creationEpoch, rolloverHour: s.rolloverHour)
    }

    // MARK: - Maintenance

    public func integrityCheck() throws -> String { try db.integrityCheck() }

    public func vacuum() throws { try db.vacuum() }

    // MARK: - Media paths

    public func mediaFileURL(_ filename: String) -> URL {
        mediaDirectory.appendingPathComponent(filename)
    }
}
