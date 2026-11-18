//
//  AnkiExporter.swift
//  Memora
//
//  Exports a deck (and subdecks) or the whole collection to a legacy .apkg
//  that Anki can import: a schema-11 `collection.anki2`, a JSON media map and
//  the referenced media files, zipped with no `meta` file (Version Legacy1 —
//  the most widely supported format).
//
//  Scheduling is converted back to Anki's representation (type/queue/due/ivl/
//  factor), and FSRS memory state is written to `cards.data`, so a round-trip
//  Memora → Anki → Memora preserves the important fields. Because this build
//  environment has no Anki to import into, the exporter is best-effort and the
//  output should be verified in Anki (see docs/LIMITATIONS.md).
//

import Foundation

public final class AnkiExporter {
    private let store: MemoraStore
    public init(store: MemoraStore) { self.store = store }

    private static let schema11 = """
    CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null,
      scm integer not null, ver integer not null, dty integer not null, usn integer not null,
      ls integer not null, conf text not null, models text not null, decks text not null,
      dconf text not null, tags text not null);
    CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null,
      mod integer not null, usn integer not null, tags text not null, flds text not null,
      sfld integer not null, csum integer not null, flags integer not null, data text not null);
    CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null,
      ord integer not null, mod integer not null, usn integer not null, type integer not null,
      queue integer not null, due integer not null, ivl integer not null, factor integer not null,
      reps integer not null, lapses integer not null, left integer not null, odue integer not null,
      odid integer not null, flags integer not null, data text not null);
    CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null,
      ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null,
      time integer not null, type integer not null);
    CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
    CREATE INDEX ix_notes_usn ON notes (usn);
    CREATE INDEX ix_cards_usn ON cards (usn);
    CREATE INDEX ix_revlog_usn ON revlog (usn);
    CREATE INDEX ix_cards_nid ON cards (nid);
    CREATE INDEX ix_cards_sched ON cards (did, queue, due);
    CREATE INDEX ix_revlog_cid ON revlog (cid);
    CREATE INDEX ix_notes_csum ON notes (csum);
    """

    public func export(deckIDs selected: [Int64]?, includeScheduling: Bool, to url: URL,
                       progress: ((Double) -> Void)? = nil) throws {
        let settings = try store.collectionSettings()
        let crt = settings.creationEpoch
        let clock = try store.dayClock()

        // Resolve the set of decks to export.
        let allDecks = try store.allDecks()
        var deckSet: [Deck]
        if let selected {
            var ids = Set<Int64>()
            for d in allDecks where selected.contains(d.id) {
                ids.formUnion(try store.descendantDeckIDs(of: d))
            }
            deckSet = allDecks.filter { ids.contains($0.id) }
        } else {
            deckSet = allDecks
        }
        if !deckSet.contains(where: { $0.id == 1 }), let def = try store.deck(id: 1) {
            deckSet.append(def)   // Anki requires the Default deck present
        }
        let deckIDSet = Set(deckSet.map { $0.id })

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("memora-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("collection.anki2")

        let db = try SQLiteDatabase(path: dbURL.path)
        try db.exec(Self.schema11)

        let notetypes = try store.allNotetypes()
        let modelsJSON = try Self.jsonString(Self.modelsDict(notetypes))
        let decksJSON = try Self.jsonString(Self.decksDict(deckSet))
        let dconfJSON = try Self.jsonString(Self.defaultDconf())
        let nextPos = (try? store.maxPosition()) ?? 0
        let confJSON = try Self.jsonString(Self.defaultConf(nextPos: Int(nextPos) + 1))

        progress?(0.1)
        try db.transaction {
            try db.run("INSERT INTO col VALUES (1,?,?,?,11,0,-1,0,?,?,?,?,?)",
                       [.integer(crt), .integer(Int64(Date().timeIntervalSince1970 * 1000)),
                        .integer(Int64(Date().timeIntervalSince1970 * 1000)),
                        .text(confJSON), .text(modelsJSON), .text(decksJSON), .text(dconfJSON), .text("{}")])

            // Collect card ids in scope, and the notes they belong to.
            let (ph, vals) = (deckIDSet.map { _ in "?" }.joined(separator: ","), deckIDSet.map { SQLiteValue.integer($0) })
            let cardRows = try db2Query(store, "SELECT \(MemoraStore.cardColumns) FROM cards WHERE deck_id IN (\(ph))", vals) { MemoraStore.card(from: $0) }

            var noteIDs = Set<Int64>()
            let noteStmt = try db.prepare("INSERT OR IGNORE INTO notes VALUES (?,?,?,?,-1,?,?,?,?,0,?)")
            let cardStmt = try db.prepare("INSERT INTO cards VALUES (?,?,?,?,?,-1,?,?,?,?,?,?,?,?,?,?,0,?)")

            for card in cardRows {
                // Insert the note once.
                if !noteIDs.contains(card.noteID), let note = try store.note(id: card.noteID) {
                    noteIDs.insert(card.noteID)
                    let sfld = TextStripping.stripHTML(note.fields.first ?? "")
                    let csum = TextStripping.fieldChecksum(note.fields.first ?? "")
                    let tagStr = note.tags.isEmpty ? "" : " " + note.tags.joined(separator: " ") + " "
                    try noteStmt.run([.integer(note.id), .text(note.guid), .integer(note.notetypeID),
                                      .integer(note.modified), .text(tagStr), .text(note.joinedFields),
                                      .text(sfld), .integer(csum), .text("")])
                }
                let anki = Self.convertCardToAnki(card, crt: crt, clock: clock, includeScheduling: includeScheduling)
                try cardStmt.run([.integer(card.id), .integer(card.noteID), .integer(card.deckID),
                                  .integer(Int64(card.templateOrd)), .integer(card.modified),
                                  .integer(Int64(anki.type)), .integer(Int64(anki.queue)), .integer(anki.due),
                                  .integer(Int64(anki.ivl)), .integer(Int64(anki.factor)), .integer(Int64(card.reps)),
                                  .integer(Int64(card.lapses)), .integer(Int64(anki.left)),
                                  .integer(anki.odue), .integer(card.originalDeckID), .text(anki.data)])
            }

            if includeScheduling {
                let revStmt = try db.prepare("INSERT INTO revlog VALUES (?,?,-1,?,?,?,?,?,?)")
                for noteID in noteIDs {
                    let cardIDs = try store.cards(forNote: noteID).map { $0.id }
                    for cid in cardIDs {
                        let logs = try self.revlogRows(forCard: cid)
                        for l in logs {
                            try revStmt.run([.integer(l.id), .integer(l.cardID), .integer(Int64(l.rating.rawValue)),
                                             .integer(Int64(l.interval)), .integer(Int64(l.lastInterval)),
                                             .integer(Int64(l.easeFactor)), .integer(Int64(l.timeMS)),
                                             .integer(Int64(l.kind.rawValue))])
                        }
                    }
                }
            }
        }
        progress?(0.6)

        // Build media map + collect files for referenced media.
        var mediaMap: [String: String] = [:]
        var mediaFiles: [(name: String, data: Data)] = []
        let referenced = try store.referencedMediaFilenames()
        var index = 0
        for name in referenced.sorted() {
            let fileURL = store.mediaFileURL(name)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            mediaMap[String(index)] = name
            mediaFiles.append((String(index), data))
            index += 1
        }
        progress?(0.8)

        // Flush the WAL into collection.anki2 and close the connection BEFORE
        // reading its bytes. The export DB was opened read-write (hence WAL
        // mode), so without this the recent INSERTs live only in the
        // collection.anki2-wal side file and the serialised collection.anki2
        // would be incomplete — reimport then fails with SQLite code 14
        // ("unable to open database file"). Closing first also prevents the
        // temp directory from being unlinked while SQLite still holds it open.
        try db.flushWALIntoMainFile()
        db.close()

        // Zip everything (no meta → Legacy1).
        let writer = ZipWriter()
        let dbBytes = try Data(contentsOf: dbURL)
        writer.add("collection.anki2", data: dbBytes, compress: true)
        let mapData = try JSONSerialization.data(withJSONObject: mediaMap)
        writer.add("media", data: mapData, compress: true)
        for file in mediaFiles { writer.add(file.name, data: file.data, compress: false) }
        let archive = writer.finish()
        try archive.write(to: url, options: .atomic)
        progress?(1.0)
    }

    // MARK: - Conversion

    struct AnkiCardFields { var type: Int; var queue: Int; var due: Int64; var ivl: Int; var factor: Int; var left: Int; var odue: Int64; var data: String }

    static func convertCardToAnki(_ card: Card, crt: Int64, clock: DayClock, includeScheduling: Bool) -> AnkiCardFields {
        if !includeScheduling || card.state == .new {
            return AnkiCardFields(type: 0, queue: card.suspended ? -1 : 0, due: card.position,
                                  ivl: 0, factor: card.easeFactor, left: 0, odue: 0, data: fsrsData(card))
        }
        let type = card.state.ankiType
        var queue: Int
        var due: Int64
        switch card.state {
        case .new:
            queue = 0; due = card.position
        case .learning, .relearning:
            queue = 1; due = card.due                 // epoch seconds
        case .review:
            queue = 2
            due = Int64((Double(card.due - crt) / 86_400).rounded())  // day number
        }
        if card.suspended { queue = -1 }
        else if card.bury == .sibling { queue = -2 }
        else if card.bury == .manual { queue = -3 }
        return AnkiCardFields(type: type, queue: queue, due: due, ivl: card.intervalDays,
                              factor: card.easeFactor, left: 0, odue: card.originalDue, data: fsrsData(card))
    }

    static func fsrsData(_ card: Card) -> String {
        guard let s = card.stability, let d = card.difficulty else { return "" }
        return "{\"s\":\(s),\"d\":\(d)}"
    }

    private func revlogRows(forCard cardID: Int64) throws -> [ReviewLog] {
        try store.db.query("""
            SELECT id, card_id, rating, ivl, last_ivl, ease, stability, difficulty, state_before, kind, time_ms, reviewed_at
            FROM revlog WHERE card_id = ? ORDER BY id
            """, [.integer(cardID)]) { row in
            ReviewLog(id: row.int(0), cardID: row.int(1), rating: Rating(rawValue: Int(row.int(2))) ?? .good,
                      interval: Int(row.int(3)), lastInterval: Int(row.int(4)), easeFactor: Int(row.int(5)),
                      stability: row.doubleOptional(6), difficulty: row.doubleOptional(7),
                      stateBefore: CardState(rawValue: Int(row.int(8))) ?? .review,
                      kind: ReviewKind(rawValue: Int(row.int(9))) ?? .review,
                      timeMS: Int(row.int(10)), reviewedAt: row.int(11))
        }
    }

    private func db2Query<T>(_ store: MemoraStore, _ sql: String, _ values: [SQLiteValue], _ transform: (SQLiteRow) throws -> T) throws -> [T] {
        try store.db.query(sql, values, transform)
    }

    // MARK: - Anki JSON builders

    static func modelsDict(_ notetypes: [Notetype]) -> [String: Any] {
        var dict: [String: Any] = [:]
        for nt in notetypes {
            let flds = nt.fields.map { f -> [String: Any] in
                ["name": f.name, "ord": f.ord, "sticky": f.sticky, "rtl": f.rightToLeft,
                 "font": f.fontFamily, "size": f.fontSize, "media": []]
            }
            let tmpls = nt.templates.map { t -> [String: Any] in
                ["name": t.name, "ord": t.ord, "qfmt": t.questionFormat, "afmt": t.answerFormat,
                 "did": t.deckOverrideID as Any? ?? NSNull(), "bqfmt": "", "bafmt": ""]
            }
            let req = nt.templates.map { t -> [Any] in [t.ord, "any", [0]] }
            dict[String(nt.id)] = [
                "id": nt.id, "name": nt.name, "type": nt.kind.rawValue, "mod": nt.modified,
                "usn": -1, "sortf": nt.sortFieldIndex, "did": 1, "css": nt.css,
                "latexPre": nt.latexPre, "latexPost": nt.latexPost, "latexsvg": false,
                "flds": flds, "tmpls": tmpls, "req": req, "vers": [], "tags": []
            ]
        }
        return dict
    }

    static func decksDict(_ decks: [Deck]) -> [String: Any] {
        var dict: [String: Any] = [:]
        for d in decks {
            dict[String(d.id)] = [
                "id": d.id, "name": d.name, "mod": d.modified, "usn": -1,
                "lrnToday": [0, 0], "revToday": [0, 0], "newToday": [0, 0], "timeToday": [0, 0],
                "collapsed": d.collapsed, "browserCollapsed": d.collapsed, "desc": "",
                "dyn": d.isFiltered ? 1 : 0, "conf": 1, "extendNew": 0, "extendRev": 0
            ]
        }
        if dict["1"] == nil {
            dict["1"] = ["id": 1, "name": "Default", "mod": 0, "usn": -1,
                         "lrnToday": [0, 0], "revToday": [0, 0], "newToday": [0, 0], "timeToday": [0, 0],
                         "collapsed": false, "browserCollapsed": false, "desc": "",
                         "dyn": 0, "conf": 1, "extendNew": 0, "extendRev": 0]
        }
        return dict
    }

    static func defaultDconf() -> [String: Any] {
        ["1": [
            "id": 1, "name": "Default", "mod": 0, "usn": -1, "maxTaken": 60, "autoplay": true,
            "timer": 0, "replayq": true,
            "new": ["bury": false, "delays": [1.0, 10.0], "initialFactor": 2500, "ints": [1, 4, 0],
                    "order": 1, "perDay": 20],
            "rev": ["bury": false, "ease4": 1.3, "ivlFct": 1.0, "maxIvl": 36500, "perDay": 200, "hardFactor": 1.2],
            "lapse": ["delays": [10.0], "leechAction": 1, "leechFails": 8, "minInt": 1, "mult": 0.0]
        ]]
    }

    static func defaultConf(nextPos: Int) -> [String: Any] {
        ["nextPos": nextPos, "estTimes": true, "activeDecks": [1], "sortType": "noteFld",
         "timeLim": 0, "sortBackwards": false, "addToCur": true, "curDeck": 1,
         "newBury": true, "newSpread": 0, "dueCounts": true, "curModel": NSNull(), "collapseTime": 1200]
    }

    static func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}
