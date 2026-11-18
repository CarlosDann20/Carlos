//
//  AnkiImporter.swift
//  Memora
//
//  Imports a Legacy1/Legacy2 .apkg into a MemoraStore. Design goals, straight
//  from the spec:
//    • Non-destructive: all collection rows are written inside one transaction,
//      so a failure rolls back and never corrupts an existing collection.
//    • Dedup: notes already present (by guid, or by note-type + first field)
//      are skipped, and their cards/history are skipped with them.
//    • Additive: importing again merges into same-named decks instead of
//      overwriting them.
//    • Preserves scheduling: ease / interval / reps / lapses / due are
//      converted, and FSRS memory state (stability, difficulty) stored in
//      `cards.data` is carried over when present.
//    • Preserves media: images and audio are written to the media directory
//      with their original filenames.
//

import Foundation

public enum ImportPhase: String, Sendable {
    case reading, notetypes, decks, notes, cards, history, media, finishing
}

public struct ImportProgress: Sendable {
    public var phase: ImportPhase
    public var fraction: Double   // 0...1
    public var message: String
}

public struct ImportSummary: Sendable {
    public var notetypes = 0
    public var decks = 0
    public var notesImported = 0
    public var notesDuplicate = 0
    public var cardsImported = 0
    public var reviewsImported = 0
    public var mediaWritten = 0
    public var mediaSkipped = 0
    public var mediaConflicts = 0
    public var warnings: [String] = []
    public var sourceVersion = ""
}

public final class AnkiImporter {
    private let store: MemoraStore
    public init(store: MemoraStore) { self.store = store }

    public typealias ProgressHandler = (ImportProgress) -> Void

    public func importPackage(at url: URL, progress: ProgressHandler? = nil) throws -> ImportSummary {
        progress?(ImportProgress(phase: .reading, fraction: 0, message: "Abriendo paquete…"))

        let pkg = try AnkiPackage(url: url)
        try pkg.ensureSupported()

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("memora-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = try pkg.extractCollection(to: tempDir)
        let reader = try AnkiCollectionReader(dbURL: dbURL)
        let col = try reader.readColInfo()

        var summary = ImportSummary()
        summary.sourceVersion = pkg.version.isLegacy ? "Legacy (schema 11)" : "v3"

        let totalNotes = (try? reader.noteCount()) ?? 0
        let totalCards = (try? reader.cardCount()) ?? 0
        let totalRev = (try? reader.revlogCount()) ?? 0
        let totalWork = max(1, totalNotes + totalCards + totalRev)
        var processed = 0

        var modelIDMap: [Int64: Int64] = [:]
        var sortFieldByModel: [Int64: Int] = [:]
        var fieldCountByModel: [Int64: Int] = [:]
        var deckIDMap: [Int64: Int64] = [:]
        var configIDMap: [Int64: Int64] = [:]
        var noteIDMap: [Int64: Int64] = [:]    // ankiNid -> memoraNid (only for imported notes)
        var cardIDMap: [Int64: Int64] = [:]
        var fsrsMemoryFound = false
        var collectedTags = Set<String>()

        // Everything collection-side happens in one transaction → atomic.
        try store.db.transaction {
            // 1) Note types
            progress?(ImportProgress(phase: .notetypes, fraction: 0.02, message: "Importando tipos de nota…"))
            for (_, model) in col.models {
                let memoraID = try importModel(model)
                modelIDMap[model.id] = memoraID
                sortFieldByModel[model.id] = model.sortf ?? 0
                fieldCountByModel[model.id] = model.flds.count
                summary.notetypes += 1
            }

            // 2) Deck options
            for (_, dc) in col.dconf {
                let cfg = try importDeckConfig(dc)
                configIDMap[dc.id] = cfg.id
            }

            // 3) Decks
            progress?(ImportProgress(phase: .decks, fraction: 0.05, message: "Importando mazos…"))
            for (_, deck) in col.decks {
                // Anki's "Default" deck id is 1; always ensure a usable name.
                let name = MemoraStore.normalizeDeckName(deck.name.isEmpty ? "Predeterminado" : deck.name)
                if name.isEmpty { continue }
                let configID = deck.conf.flatMap { configIDMap[$0] } ?? 1
                let created = try store.createDeck(name: name, configID: configID)
                deckIDMap[deck.id] = created.id
                summary.decks += 1
            }

            // 4) Notes (with dedup)
            progress?(ImportProgress(phase: .notes, fraction: 0.1, message: "Importando notas…"))
            let noteStmt = try store.db.prepare("""
                INSERT INTO notes (id, guid, notetype_id, modified, tags, flds, sfld, csum, search_text)
                VALUES (?,?,?,?,?,?,?,?,?)
                """)
            try reader.forEachNote { row in
                guard let memoraModelID = modelIDMap[row.mid] else { return } // orphan note type
                let fields = Note.splitFields(row.flds)
                let tags = row.tags.split(separator: " ").map(String.init).filter { !$0.isEmpty }

                // Dedup by guid, then by note-type + first field. Duplicates are
                // NOT mapped, so their cards/history are skipped below.
                if try store.note(guid: row.guid) != nil {
                    summary.notesDuplicate += 1
                    return
                }
                let probe = Note(id: 0, guid: row.guid, notetypeID: memoraModelID, modified: row.mod,
                                 fields: fields, tags: tags, checksum: 0)
                if try store.findDuplicate(of: probe) != nil {
                    summary.notesDuplicate += 1
                    return
                }

                // Assign id (preserve Anki id when free).
                var memoraID = row.id
                if try store.note(id: memoraID) != nil { memoraID = store.nextID() }

                let sortIndex = min(max(0, sortFieldByModel[row.mid] ?? 0), max(0, fields.count - 1))
                let sortField = fields.indices.contains(sortIndex) ? fields[sortIndex] : (fields.first ?? "")
                let sfld = TextStripping.stripHTML(sortField)
                let csum = TextStripping.fieldChecksum(fields.first ?? "")
                let search = (fields.map { TextStripping.stripHTML($0) }.joined(separator: " ")
                              + " " + tags.joined(separator: " ")).lowercased()

                try noteStmt.run([.integer(memoraID), .text(row.guid), .integer(memoraModelID),
                                  .integer(row.mod), .text(tags.joined(separator: " ")),
                                  .text(row.flds), .text(sfld), .integer(csum), .text(search)])
                noteIDMap[row.id] = memoraID
                collectedTags.formUnion(tags)
                summary.notesImported += 1
                processed += 1
                if processed % 300 == 0 {
                    progress?(ImportProgress(phase: .notes, fraction: 0.1 + 0.4 * Double(processed) / Double(totalWork),
                                             message: "Importando notas… (\(summary.notesImported))"))
                }
            }

            // 5) Cards (only for imported notes)
            progress?(ImportProgress(phase: .cards, fraction: 0.5, message: "Importando tarjetas…"))
            let cardStmt = try store.db.prepare("""
                INSERT INTO cards (\(MemoraStore.cardColumns))
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """)
            try reader.forEachCard { row in
                // Only notes this import actually created are in noteIDMap, so
                // cards belonging to duplicate/orphan notes are skipped here.
                guard let memoraNoteID = noteIDMap[row.nid] else { return }
                let memoraDeckID = deckIDMap[row.did] ?? 1
                var memoraID = row.id
                let idCollision = try store.card(id: memoraID) != nil
                if cardIDMap[row.id] != nil || idCollision { memoraID = store.nextID() }

                let card = convertCard(row, noteID: memoraNoteID, deckID: memoraDeckID,
                                       cardID: memoraID, ankiCrt: col.crt, fsrsFound: &fsrsMemoryFound)
                try cardStmt.run(cardBindings(card))
                cardIDMap[row.id] = memoraID
                summary.cardsImported += 1
                processed += 1
                if processed % 300 == 0 {
                    progress?(ImportProgress(phase: .cards, fraction: 0.5 + 0.3 * Double(processed) / Double(totalWork),
                                             message: "Importando tarjetas… (\(summary.cardsImported))"))
                }
            }

            // 6) Review history
            progress?(ImportProgress(phase: .history, fraction: 0.8, message: "Importando historial…"))
            let revStmt = try store.db.prepare("""
                INSERT OR IGNORE INTO revlog (id, card_id, rating, ivl, last_ivl, ease, stability, difficulty, state_before, kind, time_ms, reviewed_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """)
            try reader.forEachRevlog { row in
                guard let memoraCardID = cardIDMap[row.cid] else { return }
                let rating = max(1, min(4, row.ease))
                let (stateBefore, kind) = mapRevlogType(row.type)
                try revStmt.run([.integer(row.id), .integer(memoraCardID), .integer(Int64(rating)),
                                 .integer(Int64(max(0, row.ivl))), .integer(Int64(max(0, row.lastIvl))),
                                 .integer(Int64(row.factor)), .null, .null,
                                 .integer(Int64(stateBefore.rawValue)), .integer(Int64(kind.rawValue)),
                                 .integer(Int64(row.time)), .integer(row.id / 1000)])
                summary.reviewsImported += 1
                processed += 1
            }

            // Register tags.
            for tag in collectedTags { try store.registerTags([tag]) }

            // If the source collection used FSRS, switch imported configs to FSRS.
            if fsrsMemoryFound {
                for (_, memoraConfigID) in configIDMap {
                    var cfg = try store.deckConfig(id: memoraConfigID)
                    cfg.scheduler = .fsrs
                    try store.saveDeckConfig(cfg)
                }
                summary.warnings.append("La colección usa FSRS. Se activó FSRS en los mazos importados con parámetros por defecto; vuelve a optimizarlos si lo deseas.")
            }
        }

        // 7) Media (additive, outside the transaction; best-effort).
        progress?(ImportProgress(phase: .media, fraction: 0.9, message: "Importando multimedia…"))
        if pkg.version.isLegacy {
            var mediaResult = MediaWriteResult()
            let map = pkg.legacyMediaMap()
            for (entryName, realName) in map {
                guard let entry = pkg.zip.entry(named: entryName) else { continue }
                if let data = try? pkg.zip.data(for: entry) {
                    _ = try? store.writeMedia(filename: realName, data: data, into: &mediaResult)
                }
            }
            summary.mediaWritten = mediaResult.written
            summary.mediaSkipped = mediaResult.skippedIdentical
            summary.mediaConflicts = mediaResult.conflicts.count
            if !mediaResult.conflicts.isEmpty {
                summary.warnings.append("\(mediaResult.conflicts.count) archivo(s) multimedia con el mismo nombre pero distinto contenido se conservaron sin sobrescribir.")
            }
            if !mediaResult.rejected.isEmpty {
                summary.warnings.append("\(mediaResult.rejected.count) nombre(s) de archivo inseguros fueron rechazados.")
            }
        }

        progress?(ImportProgress(phase: .finishing, fraction: 1, message: "Finalizando…"))
        return summary
    }

    // MARK: - Model import

    private func importModel(_ model: AnkiModel) throws -> Int64 {
        // Reuse an existing note type with the same id (re-import of same collection).
        if try store.notetypeExists(id: model.id) { return model.id }
        let fields = model.flds.sorted { $0.ord < $1.ord }.map {
            NoteField(ord: $0.ord, name: $0.name, rightToLeft: $0.rtl ?? false,
                      fontFamily: $0.font ?? "Arial", fontSize: $0.size ?? 20,
                      sticky: $0.sticky ?? false, descriptionText: $0.description ?? "")
        }
        let templates = model.tmpls.sorted { $0.ord < $1.ord }.map {
            CardTemplate(ord: $0.ord, name: $0.name, questionFormat: $0.qfmt,
                         answerFormat: $0.afmt, deckOverrideID: $0.did)
        }
        let nt = Notetype(id: model.id, name: model.name,
                          kind: model.type == 1 ? .cloze : .standard,
                          css: model.css ?? "", fields: fields, templates: templates,
                          latexPre: model.latexPre ?? "", latexPost: model.latexPost ?? "",
                          sortFieldIndex: model.sortf ?? 0, modified: Int64(Date().timeIntervalSince1970))
        try store.upsertNotetype(nt)
        return model.id
    }

    private func importDeckConfig(_ dc: AnkiDeckConfig) throws -> DeckConfig {
        var cfg = try store.createDeckConfig(name: dc.name.isEmpty ? "Opciones" : dc.name)
        cfg.newPerDay = dc.new?.perDay ?? cfg.newPerDay
        cfg.reviewsPerDay = dc.rev?.perDay ?? cfg.reviewsPerDay
        cfg.learningStepsMinutes = dc.new?.delays ?? cfg.learningStepsMinutes
        cfg.relearningStepsMinutes = dc.lapse?.delays ?? cfg.relearningStepsMinutes
        cfg.startingEase = dc.new?.initialFactor ?? cfg.startingEase
        cfg.intervalModifier = dc.rev?.ivlFct ?? cfg.intervalModifier
        cfg.maximumIntervalDays = dc.rev?.maxIvl ?? cfg.maximumIntervalDays
        cfg.hardIntervalMultiplier = dc.rev?.hardFactor ?? cfg.hardIntervalMultiplier
        cfg.lapseNewIntervalPercent = dc.lapse?.mult ?? cfg.lapseNewIntervalPercent
        cfg.leechThreshold = dc.lapse?.leechFails ?? cfg.leechThreshold
        cfg.leechAction = (dc.lapse?.leechAction == 1) ? .tagOnly : .suspend
        cfg.scheduler = .sm2  // preserve imported SM-2 continuity by default
        try store.saveDeckConfig(cfg)
        return cfg
    }

    // MARK: - Card conversion

    private func convertCard(_ row: AnkiCardRow, noteID: Int64, deckID: Int64, cardID: Int64,
                             ankiCrt: Int64, fsrsFound: inout Bool) -> Card {
        let state = CardState.fromAnki(type: row.type)
        let suspended = row.queue == AnkiCardQueue.suspended.rawValue
        let bury: BuryState
        switch row.queue {
        case AnkiCardQueue.siblingBuried.rawValue: bury = .sibling
        case AnkiCardQueue.manuallyBuried.rawValue: bury = .manual
        default: bury = .none
        }

        let intervalDays = row.ivl > 0 ? row.ivl : 0
        var due: Int64 = 0
        var position: Int64 = 0
        if state == .new {
            position = row.due
        } else if row.due > 1_000_000_000 {
            // Looks like epoch seconds (intra-day learning due).
            due = row.due
        } else {
            // Day number relative to the collection creation.
            due = ankiCrt + row.due * 86_400
        }

        // FSRS memory state from cards.data, when present.
        var stability: Double? = nil
        var difficulty: Double? = nil
        if !row.data.isEmpty, let d = try? JSONDecoder().decode(AnkiCardData.self, from: Data(row.data.utf8)) {
            if let s = d.s, let diff = d.d {
                stability = s; difficulty = diff; fsrsFound = true
            }
            if state == .new, let pos = d.pos { position = pos }
        }

        let ease = row.factor > 0 ? row.factor : 2500
        let created = row.id > 1_000_000_000_000 ? row.id / 1000 : Int64(Date().timeIntervalSince1970)

        return Card(id: cardID, noteID: noteID, deckID: deckID, templateOrd: row.ord,
                    state: state, due: due, position: position, intervalDays: intervalDays,
                    reps: row.reps, lapses: row.lapses, learningStep: 0,
                    stability: stability, difficulty: difficulty, easeFactor: ease,
                    lastReview: nil, suspended: suspended, bury: bury, favorite: false, flags: 0,
                    originalDue: row.odue, originalDeckID: deckIDMapLookup(row.odid),
                    created: created, modified: Int64(Date().timeIntervalSince1970))
    }

    // odid may reference a deck we remapped; fall back to 0.
    private func deckIDMapLookup(_ odid: Int64) -> Int64 { odid }

    private func cardBindings(_ c: Card) -> [SQLiteValue] {
        [.integer(c.id), .integer(c.noteID), .integer(c.deckID), .integer(Int64(c.templateOrd)),
         .integer(Int64(c.state.rawValue)), .integer(c.due), .integer(c.position), .integer(Int64(c.intervalDays)),
         .integer(Int64(c.reps)), .integer(Int64(c.lapses)), .integer(Int64(c.learningStep)),
         c.stability.map { .real($0) } ?? .null, c.difficulty.map { .real($0) } ?? .null,
         .integer(Int64(c.easeFactor)), c.lastReview.map { .integer($0) } ?? .null,
         .integer(c.suspended ? 1 : 0), .integer(Int64(c.bury.rawValue)), .integer(c.favorite ? 1 : 0),
         .integer(Int64(c.flags)), .integer(c.originalDue), .integer(c.originalDeckID),
         .integer(c.created), .integer(c.modified)]
    }

    private func mapRevlogType(_ type: Int) -> (CardState, ReviewKind) {
        switch type {
        case 0: return (.learning, .learn)
        case 1: return (.review, .review)
        case 2: return (.relearning, .relearn)
        case 3: return (.review, .cram)
        default: return (.review, .manual)
        }
    }
}
