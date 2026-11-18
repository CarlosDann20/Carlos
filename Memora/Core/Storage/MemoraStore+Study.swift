//
//  MemoraStore+Study.swift
//  Memora
//
//  Queue helpers for a study session (fetch the next due card honouring the
//  deck's ordering), plus manual note creation with card generation.
//

import Foundation

extension MemoraStore {

    private func placeholders(_ ids: [Int64]) -> (String, [SQLiteValue]) {
        (ids.map { _ in "?" }.joined(separator: ","), ids.map { .integer($0) })
    }

    /// Next learning/relearning card that is due now.
    public func nextLearningCard(deckIDs: [Int64], now: Int64) throws -> Card? {
        let (ph, vals) = placeholders(deckIDs)
        let sql = """
        SELECT \(Self.cardColumns) FROM cards
        WHERE deck_id IN (\(ph)) AND state IN (1,3) AND suspended = 0 AND bury = 0 AND due <= ?
        ORDER BY due ASC LIMIT 1
        """
        return try db.query(sql, vals + [.integer(now)]) { Self.card(from: $0) }.first
    }

    public func nextReviewCard(deckIDs: [Int64], endOfToday: Int64, order: ReviewCardOrder) throws -> Card? {
        let (ph, vals) = placeholders(deckIDs)
        let orderBy: String
        switch order {
        case .dueDateThenRandom: orderBy = "due ASC, RANDOM()"
        case .due: orderBy = "due ASC, id ASC"
        case .random: orderBy = "RANDOM()"
        }
        let sql = """
        SELECT \(Self.cardColumns) FROM cards
        WHERE deck_id IN (\(ph)) AND state = 2 AND suspended = 0 AND bury = 0 AND due <= ?
        ORDER BY \(orderBy) LIMIT 1
        """
        return try db.query(sql, vals + [.integer(endOfToday)]) { Self.card(from: $0) }.first
    }

    public func nextNewCard(deckIDs: [Int64], order: NewCardOrder, excluding: Set<Int64> = []) throws -> Card? {
        let (ph, vals) = placeholders(deckIDs)
        let orderBy = order == .random ? "RANDOM()" : "position ASC, id ASC"
        let sql = """
        SELECT \(Self.cardColumns) FROM cards
        WHERE deck_id IN (\(ph)) AND state = 0 AND suspended = 0 AND bury = 0
        ORDER BY \(orderBy) LIMIT 50
        """
        let candidates = try db.query(sql, vals) { Self.card(from: $0) }
        return candidates.first { !excluding.contains($0.id) }
    }

    public func newIntroducedToday(deckIDs: [Int64], start: Int64, now: Int64) throws -> Int {
        let (ph, vals) = placeholders(deckIDs)
        return Int(try db.scalarInt("""
            SELECT COUNT(*) FROM revlog WHERE state_before = 0 AND reviewed_at >= ? AND reviewed_at <= ?
            AND card_id IN (SELECT id FROM cards WHERE deck_id IN (\(ph)))
            """, [.integer(start), .integer(now)] + vals))
    }

    public func reviewsDoneToday(deckIDs: [Int64], start: Int64, now: Int64) throws -> Int {
        let (ph, vals) = placeholders(deckIDs)
        return Int(try db.scalarInt("""
            SELECT COUNT(*) FROM revlog WHERE state_before = 2 AND reviewed_at >= ? AND reviewed_at <= ?
            AND card_id IN (SELECT id FROM cards WHERE deck_id IN (\(ph)))
            """, [.integer(start), .integer(now)] + vals))
    }

    public func deleteRevlog(id: Int64) throws {
        try db.run("DELETE FROM revlog WHERE id = ?", [.integer(id)])
    }

    // MARK: - Manual note creation

    /// Create a note and generate its cards. For standard note types a card is
    /// generated per template whose question renders non-empty; for cloze note
    /// types, one card per distinct cloze number present in the content.
    @discardableResult
    public func addNote(notetypeID: Int64, deckID: Int64, fields: [String], tags: [String]) throws -> Note {
        guard let nt = try notetype(id: notetypeID) else {
            throw MemoraError(.notFound, "Tipo de nota no encontrado.")
        }
        let now = Int64(Date().timeIntervalSince1970)
        let nid = nextID()
        let note = Note(id: nid, guid: Self.makeGUID(), notetypeID: notetypeID, modified: now,
                        fields: fields, tags: tags, checksum: 0)
        try db.transaction {
            try saveNote(note)
            let cards = try generateCards(for: note, notetype: nt, deckID: deckID, now: now)
            var pos = try maxPosition() + 1
            for var card in cards {
                card.position = pos
                pos += 1
                try saveCard(card)
            }
        }
        return note
    }

    /// Regenerate cards after a note edit (adds newly-required cards; does not
    /// delete existing ones to preserve scheduling).
    public func syncCards(for note: Note, deckID: Int64) throws {
        guard let nt = try notetype(id: note.notetypeID) else { return }
        let existing = try cards(forNote: note.id)
        let existingOrds = Set(existing.map { $0.templateOrd })
        let now = Int64(Date().timeIntervalSince1970)
        let required = try generateCards(for: note, notetype: nt, deckID: deckID, now: now)
        var pos = try maxPosition() + 1
        for var card in required where !existingOrds.contains(card.templateOrd) {
            card.position = pos; pos += 1
            try saveCard(card)
        }
    }

    private func generateCards(for note: Note, notetype nt: Notetype, deckID: Int64, now: Int64) throws -> [Card] {
        var result: [Card] = []
        if nt.kind == .cloze {
            let field = note.fields.first ?? ""
            var nums = ClozeRenderer.clozeNumbers(in: note.fields.joined(separator: " "))
            if nums.isEmpty { nums = [1] }
            for n in nums.sorted() {
                result.append(makeNewCard(noteID: note.id, deckID: deckID, ord: n - 1, now: now))
            }
            _ = field
        } else {
            for template in nt.templates {
                let rendered = CardRenderer.render(
                    card: makeNewCard(noteID: note.id, deckID: deckID, ord: template.ord, now: now),
                    note: note, notetype: nt)
                let q = TextStripping.stripHTML(rendered.questionHTML).trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty {
                    result.append(makeNewCard(noteID: note.id, deckID: deckID, ord: template.ord, now: now))
                }
            }
            if result.isEmpty, let first = nt.templates.first {
                result.append(makeNewCard(noteID: note.id, deckID: deckID, ord: first.ord, now: now))
            }
        }
        return result
    }

    private func makeNewCard(noteID: Int64, deckID: Int64, ord: Int, now: Int64) -> Card {
        Card(id: nextID(), noteID: noteID, deckID: deckID, templateOrd: ord,
             state: .new, due: 0, position: 0, intervalDays: 0, reps: 0, lapses: 0,
             learningStep: 0, stability: nil, difficulty: nil, easeFactor: 2500,
             lastReview: nil, suspended: false, bury: .none, favorite: false, flags: 0,
             originalDue: 0, originalDeckID: 0, created: now, modified: now)
    }

    static func makeGUID() -> String {
        // Short, URL-safe base64 of random bytes (Anki-style 10-char guid).
        var bytes = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 { bytes[i] = UInt8.random(in: 0...255) }
        let b64 = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return String(b64.prefix(10))
    }
}
