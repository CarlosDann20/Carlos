//
//  MemoraStore+Media.swift
//  Memora
//
//  Media files (images, audio) are stored as real files in the collection's
//  media directory and tracked in the `media` table for dedup and backup.
//  Filenames are sanitised to prevent path traversal (a malicious .apkg could
//  otherwise try to write outside the sandbox).
//

import Foundation

public struct MediaWriteResult: Sendable {
    public var written: Int = 0
    public var skippedIdentical: Int = 0
    public var conflicts: [String] = []   // same name, different content (kept existing)
    public var rejected: [String] = []    // unsafe filename
}

extension MemoraStore {

    /// Remove any path components and reject unsafe names. Returns nil if the
    /// name cannot be made safe.
    public static func sanitizeMediaFilename(_ raw: String) -> String? {
        // Take the last path component only, drop control chars.
        let base = (raw as NSString).lastPathComponent
        let cleaned = base.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." { return nil }
        if cleaned.contains("/") || cleaned.contains("\\") { return nil }
        return cleaned
    }

    @discardableResult
    public func writeMedia(filename rawName: String, data: Data, into result: inout MediaWriteResult) throws -> String? {
        guard let name = Self.sanitizeMediaFilename(rawName) else {
            result.rejected.append(rawName)
            return nil
        }
        let sha = SHA1.hexString(data)
        let url = mediaFileURL(name)
        let fm = FileManager.default

        if fm.fileExists(atPath: url.path) {
            // Compare content.
            if let existing = try? Data(contentsOf: url), existing == data {
                result.skippedIdentical += 1
                return name
            }
            if let existingItem = try mediaItem(filename: name), existingItem.sha1 == sha {
                result.skippedIdentical += 1
                return name
            }
            // Same name, different content: keep existing to protect other decks.
            result.conflicts.append(name)
            return name
        }

        // Ensure we never escape the media directory.
        guard url.path.hasPrefix(mediaDirectory.path) else {
            result.rejected.append(rawName)
            return nil
        }
        try data.write(to: url, options: .atomic)
        try upsertMedia(MediaItem(filename: name, size: data.count, sha1Hex: sha))
        result.written += 1
        return name
    }

    public func upsertMedia(_ item: MediaItem) throws {
        try db.run("""
            INSERT INTO media (filename, size, sha1) VALUES (?, ?, ?)
            ON CONFLICT(filename) DO UPDATE SET size = excluded.size, sha1 = excluded.sha1
            """, [.text(item.filename), .integer(Int64(item.size)), .text(item.sha1Hex)])
    }

    public func mediaItem(filename: String) throws -> MediaItem? {
        try db.query("SELECT filename, size, sha1 FROM media WHERE filename = ?", [.text(filename)]) {
            MediaItem(filename: $0.string(0), size: Int($0.int(1)), sha1Hex: $0.string(2))
        }.first
    }

    public func allMedia() throws -> [MediaItem] {
        try db.query("SELECT filename, size, sha1 FROM media ORDER BY filename") {
            MediaItem(filename: $0.string(0), size: Int($0.int(1)), sha1Hex: $0.string(2))
        }
    }

    public func mediaCount() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM media")) }

    public func totalMediaBytes() throws -> Int64 { try db.scalarInt("SELECT COALESCE(SUM(size),0) FROM media") }

    /// Filenames actually referenced by note fields: `<img src="...">` and
    /// `[sound:...]`. Used to prune unused media during backup/cleanup.
    public func referencedMediaFilenames() throws -> Set<String> {
        var names = Set<String>()
        let fields = try db.query("SELECT flds FROM notes") { $0.string(0) }
        for f in fields {
            names.formUnion(MediaReferences.extract(from: f))
        }
        return names
    }
}
