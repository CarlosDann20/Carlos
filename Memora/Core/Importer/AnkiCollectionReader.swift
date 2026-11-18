//
//  AnkiCollectionReader.swift
//  Memora
//
//  Reads a schema-11 Anki collection database (the `collection.anki2` /
//  `collection.anki21` extracted from an .apkg). Rows are streamed via
//  prepared statements so a collection with tens of thousands of cards does
//  not have to be materialised in memory at once.
//

import Foundation

final class AnkiCollectionReader {
    let db: SQLiteDatabase

    struct ColInfo {
        var crt: Int64
        var models: [String: AnkiModel]
        var decks: [String: AnkiDeck]
        var dconf: [String: AnkiDeckConfig]
    }

    init(dbURL: URL) throws {
        do {
            self.db = try SQLiteDatabase(path: dbURL.path, readOnly: true)
        } catch {
            throw MemoraError.corrupt("No se pudo abrir la colección del paquete.", underlying: error)
        }
    }

    func readColInfo() throws -> ColInfo {
        let rows = try db.query("SELECT crt, models, decks, dconf FROM col LIMIT 1") { row in
            (row.int(0), row.string(1), row.string(2), row.string(3))
        }
        guard let row = rows.first else {
            throw MemoraError.corrupt("La colección del paquete no tiene tabla 'col'.")
        }
        let decoder = JSONDecoder()
        let models = (try? decoder.decode([String: AnkiModel].self, from: Data(row.1.utf8))) ?? [:]
        let decks = (try? decoder.decode([String: AnkiDeck].self, from: Data(row.2.utf8))) ?? [:]
        let dconf = (try? decoder.decode([String: AnkiDeckConfig].self, from: Data(row.3.utf8))) ?? [:]
        if models.isEmpty {
            throw MemoraError.corrupt("La colección no contiene tipos de nota legibles (¿formato no soportado?).")
        }
        return ColInfo(crt: row.0, models: models, decks: decks, dconf: dconf)
    }

    func noteCount() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM notes")) }
    func cardCount() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM cards")) }
    func revlogCount() throws -> Int {
        (try? db.scalarInt("SELECT COUNT(*) FROM revlog")).map(Int.init) ?? 0
    }

    func forEachNote(_ body: (AnkiNoteRow) throws -> Void) throws {
        let stmt = try db.prepare("SELECT id, guid, mid, mod, tags, flds FROM notes")
        try stmt.forEachRow { row in
            try body(AnkiNoteRow(id: row.int(0), guid: row.string(1), mid: row.int(2),
                                 mod: row.int(3), tags: row.string(4), flds: row.string(5)))
        }
    }

    func forEachCard(_ body: (AnkiCardRow) throws -> Void) throws {
        let stmt = try db.prepare("""
            SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, data
            FROM cards
            """)
        try stmt.forEachRow { row in
            try body(AnkiCardRow(id: row.int(0), nid: row.int(1), did: row.int(2), ord: Int(row.int(3)),
                                 type: Int(row.int(4)), queue: Int(row.int(5)), due: row.int(6),
                                 ivl: Int(row.int(7)), factor: Int(row.int(8)), reps: Int(row.int(9)),
                                 lapses: Int(row.int(10)), left: Int(row.int(11)), odue: row.int(12),
                                 odid: row.int(13), data: row.stringOptional(14) ?? ""))
        }
    }

    func forEachRevlog(_ body: (AnkiRevlogRow) throws -> Void) throws {
        // revlog may be absent in some packages.
        guard (try? db.scalarInt("SELECT COUNT(*) FROM revlog")) != nil else { return }
        let stmt = try db.prepare("SELECT id, cid, ease, ivl, lastIvl, factor, time, type FROM revlog")
        try stmt.forEachRow { row in
            try body(AnkiRevlogRow(id: row.int(0), cid: row.int(1), ease: Int(row.int(2)),
                                   ivl: Int(row.int(3)), lastIvl: Int(row.int(4)), factor: Int(row.int(5)),
                                   time: Int(row.int(6)), type: Int(row.int(7))))
        }
    }
}
