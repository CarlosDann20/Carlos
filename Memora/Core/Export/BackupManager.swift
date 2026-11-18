//
//  BackupManager.swift
//  Memora
//
//  Local backup and restore. A backup is a single .memora (ZIP) file holding a
//  consistent snapshot of the collection database (via SQLite's online backup
//  API) plus every media file and a manifest. Restore validates the snapshot's
//  integrity BEFORE replacing anything, so a corrupt backup can never destroy a
//  working collection.
//

import Foundation

public struct BackupManifest: Codable, Sendable {
    public var format: String = "memora-backup"
    public var version: Int = 1
    public var createdAt: Int64
    public var noteCount: Int
    public var cardCount: Int
    public var mediaCount: Int
}

public enum BackupManager {

    public static func createBackup(store: MemoraStore, to url: URL,
                                    progress: ((Double) -> Void)? = nil) throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("memora-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Consistent DB snapshot.
        let snapshot = tempDir.appendingPathComponent("collection.sqlite")
        try store.db.backup(to: snapshot.path)
        progress?(0.3)

        let writer = ZipWriter()
        writer.add("collection.sqlite", data: try Data(contentsOf: snapshot), compress: true)

        let media = try store.allMedia()
        var written = 0
        for item in media {
            let fileURL = store.mediaFileURL(item.filename)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            writer.add("media/\(item.filename)", data: data, compress: false)
            written += 1
            if written % 50 == 0 { progress?(0.3 + 0.6 * Double(written) / Double(max(1, media.count))) }
        }

        let manifest = BackupManifest(createdAt: Int64(Date().timeIntervalSince1970),
                                      noteCount: (try? store.noteCount()) ?? 0,
                                      cardCount: (try? store.cardCount()) ?? 0,
                                      mediaCount: media.count)
        writer.add("manifest.json", data: try JSONEncoder().encode(manifest), compress: true)

        try writer.finish().write(to: url, options: .atomic)
        progress?(1.0)
    }

    /// Validate and restore a backup into the given locations. Returns the
    /// manifest on success. Throws (without modifying the targets) if the
    /// backup is invalid or its database fails an integrity check.
    @discardableResult
    public static func restore(from url: URL, databaseURL: URL, mediaDirectory: URL,
                               progress: ((Double) -> Void)? = nil) throws -> BackupManifest {
        let zip = try ZipReader(url: url)
        guard zip.contains("collection.sqlite") else {
            throw MemoraError.corrupt("La copia de seguridad no contiene la base de datos.")
        }
        let manifest: BackupManifest
        if let mData = try? zip.data(forName: "manifest.json"),
           let m = try? JSONDecoder().decode(BackupManifest.self, from: mData) {
            manifest = m
        } else {
            manifest = BackupManifest(createdAt: 0, noteCount: 0, cardCount: 0, mediaCount: 0)
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("memora-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Extract + validate the database BEFORE replacing anything.
        let stagedDB = tempDir.appendingPathComponent("collection.sqlite")
        try zip.data(forName: "collection.sqlite").write(to: stagedDB, options: .atomic)
        let check = try SQLiteDatabase(path: stagedDB.path, readOnly: true).integrityCheck()
        guard check == "ok" else {
            throw MemoraError.corrupt("La base de datos de la copia está dañada (\(check)); no se restauró nada.")
        }
        progress?(0.4)

        // Stage media.
        let stagedMedia = tempDir.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: stagedMedia, withIntermediateDirectories: true)
        for entry in zip.entries where entry.name.hasPrefix("media/") {
            let rel = String(entry.name.dropFirst("media/".count))
            guard let safe = MemoraStore.sanitizeMediaFilename(rel) else { continue }
            if let data = try? zip.data(for: entry) {
                try? data.write(to: stagedMedia.appendingPathComponent(safe), options: .atomic)
            }
        }
        progress?(0.7)

        // Swap in the validated data. Remove the old WAL/SHM side files too.
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let p = URL(fileURLWithPath: databaseURL.path + suffix)
            if fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        }
        try fm.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: stagedDB, to: databaseURL)

        if fm.fileExists(atPath: mediaDirectory.path) { try? fm.removeItem(at: mediaDirectory) }
        try fm.createDirectory(at: mediaDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: stagedMedia, to: mediaDirectory)
        progress?(1.0)
        return manifest
    }
}
