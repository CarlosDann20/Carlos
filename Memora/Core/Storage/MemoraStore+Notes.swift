//
//  MemoraStore+Notes.swift
//  Memora
//

import Foundation

extension MemoraStore {

    private static let noteColumns = "id, guid, notetype_id, modified, tags, flds, csum"

    private static func note(from row: SQLiteRow) -> Note {
        let tagStr = row.string(4)
        let tags = tagStr.split(whereSeparator: { $0 == " " }).map(String.init).filter { !$0.isEmpty }
        return Note(id: row.int(0), guid: row.string(1), notetypeID: row.int(2),
                    modified: row.int(3), fields: Note.splitFields(row.string(5)),
                    tags: tags, checksum: row.int(6))
    }

    /// Derived values for storage: stripped sort field, checksum, search text.
    private func derived(for note: Note) throws -> (sfld: String, csum: Int64, search: String) {
        let sortIndex: Int
        if let nt = try notetype(id: note.notetypeID) {
            sortIndex = min(max(0, nt.sortFieldIndex), max(0, note.fields.count - 1))
        } else {
            sortIndex = 0
        }
        let sortField = note.fields.indices.contains(sortIndex) ? note.fields[sortIndex] : (note.fields.first ?? "")
        let sfld = TextStripping.stripHTML(sortField)
        let csum = TextStripping.fieldChecksum(note.fields.first ?? "")
        let search = (note.fields.map { TextStripping.stripHTML($0) }.joined(separator: " ") + " " + note.tags.joined(separator: " ")).lowercased()
        return (sfld, csum, search)
    }

    public func saveNote(_ note: Note) throws {
        let d = try derived(for: note)
        let tagStr = note.tags.joined(separator: " ")
        try db.run("""
            INSERT INTO notes (id, guid, notetype_id, modified, tags, flds, sfld, csum, search_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              guid = excluded.guid, notetype_id = excluded.notetype_id, modified = excluded.modified,
              tags = excluded.tags, flds = excluded.flds, sfld = excluded.sfld,
              csum = excluded.csum, search_text = excluded.search_text
            """, [.integer(note.id), .text(note.guid), .integer(note.notetypeID),
                  .integer(note.modified), .text(tagStr), .text(note.joinedFields),
                  .text(d.sfld), .integer(d.csum), .text(d.search)])
        try registerTags(note.tags)
    }

    public func note(id: Int64) throws -> Note? {
        try db.query("SELECT \(Self.noteColumns) FROM notes WHERE id = ?", [.integer(id)]) { Self.note(from: $0) }.first
    }

    public func note(guid: String) throws -> Note? {
        try db.query("SELECT \(Self.noteColumns) FROM notes WHERE guid = ? LIMIT 1", [.text(guid)]) { Self.note(from: $0) }.first
    }

    public func deleteNote(id: Int64) throws {
        try db.transaction {
            try db.run("DELETE FROM revlog WHERE card_id IN (SELECT id FROM cards WHERE note_id = ?)", [.integer(id)])
            try db.run("DELETE FROM cards WHERE note_id = ?", [.integer(id)])
            try db.run("DELETE FROM notes WHERE id = ?", [.integer(id)])
        }
    }

    /// Find a duplicate of `note` within the same note type: Anki compares the
    /// checksum of the first field and then the stripped text for an exact
    /// match. Returns the first matching stored note, if any.
    public func findDuplicate(of note: Note) throws -> Note? {
        let csum = TextStripping.fieldChecksum(note.fields.first ?? "")
        let candidates = try db.query(
            "SELECT \(Self.noteColumns) FROM notes WHERE notetype_id = ? AND csum = ?",
            [.integer(note.notetypeID), .integer(csum)]) { Self.note(from: $0) }
        let target = TextStripping.normalizedForDedup(note.fields.first ?? "")
        return candidates.first { TextStripping.normalizedForDedup($0.fields.first ?? "") == target }
    }

    public func noteCount() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM notes")) }

    // MARK: - Tags

    public func registerTags(_ tags: [String]) throws {
        for tag in tags where !tag.isEmpty {
            try db.run("INSERT OR IGNORE INTO tags (name) VALUES (?)", [.text(tag)])
        }
    }

    public func allTags() throws -> [String] {
        try db.query("SELECT name FROM tags ORDER BY name COLLATE NOCASE") { $0.string(0) }
    }

    public func addTag(_ tag: String, toNote noteID: Int64) throws {
        guard var note = try note(id: noteID) else { return }
        if !note.tags.contains(tag) {
            note.tags.append(tag)
            note.modified = Int64(Date().timeIntervalSince1970)
            try saveNote(note)
        }
    }
}
