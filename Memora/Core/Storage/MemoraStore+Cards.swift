//
//  MemoraStore+Cards.swift
//  Memora
//

import Foundation

extension MemoraStore {

    static let cardColumns = """
    id, note_id, deck_id, ord, state, due, position, ivl, reps, lapses, learn_step,
    stability, difficulty, ease, last_review, suspended, bury, favorite, flags,
    odue, odid, created, modified
    """

    static func card(from row: SQLiteRow) -> Card {
        Card(id: row.int(0), noteID: row.int(1), deckID: row.int(2), templateOrd: Int(row.int(3)),
             state: CardState(rawValue: Int(row.int(4))) ?? .new, due: row.int(5), position: row.int(6),
             intervalDays: Int(row.int(7)), reps: Int(row.int(8)), lapses: Int(row.int(9)),
             learningStep: Int(row.int(10)), stability: row.doubleOptional(11), difficulty: row.doubleOptional(12),
             easeFactor: Int(row.int(13)), lastReview: row.intOptional(14),
             suspended: row.int(15) != 0, bury: BuryState(rawValue: Int(row.int(16))) ?? .none,
             favorite: row.int(17) != 0, flags: Int(row.int(18)),
             originalDue: row.int(19), originalDeckID: row.int(20),
             created: row.int(21), modified: row.int(22))
    }

    public func saveCard(_ card: Card) throws {
        try db.run("""
            INSERT INTO cards (\(Self.cardColumns))
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              note_id=excluded.note_id, deck_id=excluded.deck_id, ord=excluded.ord, state=excluded.state,
              due=excluded.due, position=excluded.position, ivl=excluded.ivl, reps=excluded.reps,
              lapses=excluded.lapses, learn_step=excluded.learn_step, stability=excluded.stability,
              difficulty=excluded.difficulty, ease=excluded.ease, last_review=excluded.last_review,
              suspended=excluded.suspended, bury=excluded.bury, favorite=excluded.favorite,
              flags=excluded.flags, odue=excluded.odue, odid=excluded.odid, modified=excluded.modified
            """, cardBindings(card))
    }

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

    public func card(id: Int64) throws -> Card? {
        try db.query("SELECT \(Self.cardColumns) FROM cards WHERE id = ?", [.integer(id)]) { Self.card(from: $0) }.first
    }

    public func cards(forNote noteID: Int64) throws -> [Card] {
        try db.query("SELECT \(Self.cardColumns) FROM cards WHERE note_id = ? ORDER BY ord", [.integer(noteID)]) { Self.card(from: $0) }
    }

    public func cardCount() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM cards")) }

    public func maxPosition() throws -> Int64 { try db.scalarInt("SELECT COALESCE(MAX(position),0) FROM cards") }

    // MARK: - Review persistence

    /// Persist the result of a review atomically: update the card, append the
    /// review log, and apply a "leech" tag when requested. This is the write
    /// path used after every answer.
    public func commit(_ result: ReviewResult, leechAction: LeechAction) throws {
        try db.transaction {
            try saveCard(result.card)
            try db.run("""
                INSERT INTO revlog (id, card_id, rating, ivl, last_ivl, ease, stability, difficulty, state_before, kind, time_ms, reviewed_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """, [.integer(result.log.id), .integer(result.log.cardID), .integer(Int64(result.log.rating.rawValue)),
                      .integer(Int64(result.log.interval)), .integer(Int64(result.log.lastInterval)),
                      .integer(Int64(result.log.easeFactor)),
                      result.log.stability.map { .real($0) } ?? .null,
                      result.log.difficulty.map { .real($0) } ?? .null,
                      .integer(Int64(result.log.stateBefore.rawValue)), .integer(Int64(result.log.kind.rawValue)),
                      .integer(Int64(result.log.timeMS)), .integer(result.log.reviewedAt)])
            if result.becameLeech && leechAction == .tagOnly {
                try addTag("leech", toNote: result.card.noteID)
            }
        }
    }

    // MARK: - Card state operations

    public func setSuspended(_ suspended: Bool, cardIDs: [Int64]) throws {
        try updateFlag("suspended", value: suspended ? 1 : 0, cardIDs: cardIDs)
    }

    public func setFavorite(_ favorite: Bool, cardIDs: [Int64]) throws {
        try updateFlag("favorite", value: favorite ? 1 : 0, cardIDs: cardIDs)
    }

    public func setFlag(_ flag: Int, cardIDs: [Int64]) throws {
        try updateFlag("flags", value: Int64(flag), cardIDs: cardIDs)
    }

    public func setBury(_ bury: BuryState, cardIDs: [Int64]) throws {
        try updateFlag("bury", value: Int64(bury.rawValue), cardIDs: cardIDs)
    }

    private func updateFlag(_ column: String, value: Int64, cardIDs: [Int64]) throws {
        guard !cardIDs.isEmpty else { return }
        let placeholders = cardIDs.map { _ in "?" }.joined(separator: ",")
        let values: [SQLiteValue] = [.integer(value)] + cardIDs.map { .integer($0) }
        try db.run("UPDATE cards SET \(column) = ? WHERE id IN (\(placeholders))", values)
    }

    /// Clear sibling/manual burying (called at the start of each study day).
    public func unburyAll() throws {
        try db.run("UPDATE cards SET bury = 0 WHERE bury != 0")
    }

    public func unburyDeck(_ deck: Deck) throws {
        let ids = try descendantDeckIDs(of: deck)
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        try db.run("UPDATE cards SET bury = 0 WHERE bury != 0 AND deck_id IN (\(placeholders))",
                   ids.map { .integer($0) })
    }

    /// Reset a card's scheduling back to "new" (used by "forget").
    public func resetCard(id: Int64) throws {
        guard var card = try card(id: id) else { return }
        card.state = .new
        card.due = 0
        card.intervalDays = 0
        card.reps = 0
        card.lapses = 0
        card.learningStep = 0
        card.stability = nil
        card.difficulty = nil
        card.easeFactor = 2500
        card.lastReview = nil
        card.modified = Int64(Date().timeIntervalSince1970)
        try saveCard(card)
    }
}
