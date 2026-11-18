//
//  MemoraStore+Decks.swift
//  Memora
//
//  Deck and deck-config operations, including hierarchy management and the
//  aggregated study counts shown in the deck list.
//

import Foundation

extension MemoraStore {

    // MARK: - Deck config

    public func allDeckConfigs() throws -> [DeckConfig] {
        try db.query("SELECT json FROM deck_config ORDER BY id") { row in
            try Self.decodeConfig(row.string(0))
        }
    }

    public func deckConfig(id: Int64) throws -> DeckConfig {
        let rows = try db.query("SELECT json FROM deck_config WHERE id = ?", [.integer(id)]) { row in
            try Self.decodeConfig(row.string(0))
        }
        return rows.first ?? .makeDefault()
    }

    /// Resolve the effective config for a deck (falls back to the default).
    public func config(for deck: Deck) throws -> DeckConfig {
        try deckConfig(id: deck.configID)
    }

    public func saveDeckConfig(_ config: DeckConfig) throws {
        let json = try Self.encodeConfig(config)
        try db.run("INSERT INTO deck_config (id, name, json) VALUES (?, ?, ?) " +
                   "ON CONFLICT(id) DO UPDATE SET name = excluded.name, json = excluded.json",
                   [.integer(config.id), .text(config.name), .text(json)])
    }

    public func createDeckConfig(name: String, basedOn: DeckConfig = .makeDefault()) throws -> DeckConfig {
        let id = try (db.scalarInt("SELECT COALESCE(MAX(id),0) FROM deck_config") + 1)
        var config = basedOn
        config.id = id
        config.name = name
        try saveDeckConfig(config)
        return config
    }

    private static func decodeConfig(_ json: String) throws -> DeckConfig {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(DeckConfig.self, from: data)
    }

    private static func encodeConfig(_ config: DeckConfig) throws -> String {
        let data = try JSONEncoder().encode(config)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Decks

    private static let deckColumns = "id, name, parent_id, config_id, collapsed, filtered, created, modified"

    private static func deck(from row: SQLiteRow) -> Deck {
        Deck(id: row.int(0), name: row.string(1), parentID: row.intOptional(2),
             configID: row.int(3), collapsed: row.int(4) != 0, isFiltered: row.int(5) != 0,
             created: row.int(6), modified: row.int(7))
    }

    public func allDecks() throws -> [Deck] {
        try db.query("SELECT \(Self.deckColumns) FROM decks ORDER BY name") { Self.deck(from: $0) }
    }

    public func deck(id: Int64) throws -> Deck? {
        try db.query("SELECT \(Self.deckColumns) FROM decks WHERE id = ?", [.integer(id)]) { Self.deck(from: $0) }.first
    }

    public func deck(name: String) throws -> Deck? {
        try db.query("SELECT \(Self.deckColumns) FROM decks WHERE name = ?", [.text(name)]) { Self.deck(from: $0) }.first
    }

    /// Create a deck by full name, creating any missing parents (as in Anki).
    @discardableResult
    public func createDeck(name rawName: String, configID: Int64 = 1) throws -> Deck {
        let name = Self.normalizeDeckName(rawName)
        if let existing = try deck(name: name) { return existing }
        let now = Int64(Date().timeIntervalSince1970)
        var parentID: Int64? = nil
        let parts = name.components(separatedBy: Deck.separator)
        if parts.count > 1 {
            let parentName = parts.dropLast().joined(separator: Deck.separator)
            let parent = try createDeck(name: parentName, configID: configID)
            parentID = parent.id
        }
        let id = nextID()
        try db.run("""
            INSERT INTO decks (id, name, parent_id, config_id, collapsed, filtered, created, modified)
            VALUES (?, ?, ?, ?, 0, 0, ?, ?)
            """, [.integer(id), .text(name), parentID.map { .integer($0) } ?? .null,
                  .integer(configID), .integer(now), .integer(now)])
        return Deck(id: id, name: name, parentID: parentID, configID: configID,
                    created: now, modified: now)
    }

    public func renameDeck(id: Int64, to newRawName: String) throws {
        guard let old = try deck(id: id) else { throw MemoraError(.notFound, "El mazo no existe.") }
        let newName = Self.normalizeDeckName(newRawName)
        guard newName != old.name else { return }
        if try deck(name: newName) != nil {
            throw MemoraError(.invalidState, "Ya existe un mazo llamado '\(newName)'.")
        }
        let now = Int64(Date().timeIntervalSince1970)
        try db.transaction {
            // Ensure parents exist for the new name.
            var parentID: Int64? = nil
            let parts = newName.components(separatedBy: Deck.separator)
            if parts.count > 1 {
                let parent = try createDeck(name: parts.dropLast().joined(separator: Deck.separator))
                parentID = parent.id
            }
            try db.run("UPDATE decks SET name = ?, parent_id = ?, modified = ? WHERE id = ?",
                       [.text(newName), parentID.map { .integer($0) } ?? .null, .integer(now), .integer(id)])
            // Rename descendants, rewriting their name prefix.
            let prefix = old.name + Deck.separator
            let children = try db.query("SELECT \(Self.deckColumns) FROM decks WHERE name LIKE ?",
                                        [.text(prefix + "%")]) { Self.deck(from: $0) }
            for child in children {
                let suffix = String(child.name.dropFirst(old.name.count))
                try db.run("UPDATE decks SET name = ?, modified = ? WHERE id = ?",
                           [.text(newName + suffix), .integer(now), .integer(child.id)])
            }
        }
    }

    /// Ids of a deck and all its descendants.
    public func descendantDeckIDs(of deck: Deck) throws -> [Int64] {
        var ids = [deck.id]
        let prefix = deck.name + Deck.separator
        let children = try db.query("SELECT id FROM decks WHERE name LIKE ?", [.text(prefix + "%")]) { $0.int(0) }
        ids.append(contentsOf: children)
        return ids
    }

    public func deleteDeck(id: Int64, deleteCards: Bool = true) throws {
        guard let deck = try deck(id: id) else { return }
        let ids = try descendantDeckIDs(of: deck)
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let values = ids.map { SQLiteValue.integer($0) }
        try db.transaction {
            if deleteCards {
                // Delete revlog, cards, then orphan notes.
                try db.run("DELETE FROM revlog WHERE card_id IN (SELECT id FROM cards WHERE deck_id IN (\(placeholders)))", values)
                try db.run("DELETE FROM cards WHERE deck_id IN (\(placeholders))", values)
                try db.run("DELETE FROM notes WHERE id NOT IN (SELECT DISTINCT note_id FROM cards)")
            } else {
                // Move cards to the Default deck.
                try db.run("UPDATE cards SET deck_id = 1 WHERE deck_id IN (\(placeholders))", values)
            }
            try db.run("DELETE FROM decks WHERE id IN (\(placeholders))", values)
        }
    }

    public func setDeckCollapsed(id: Int64, collapsed: Bool) throws {
        try db.run("UPDATE decks SET collapsed = ? WHERE id = ?", [.integer(collapsed ? 1 : 0), .integer(id)])
    }

    public func setDeckConfig(deckID: Int64, configID: Int64) throws {
        try db.run("UPDATE decks SET config_id = ? WHERE id = ?", [.integer(configID), .integer(deckID)])
    }

    public func moveCards(_ cardIDs: [Int64], toDeck deckID: Int64) throws {
        guard !cardIDs.isEmpty else { return }
        let placeholders = cardIDs.map { _ in "?" }.joined(separator: ",")
        let values: [SQLiteValue] = [.integer(deckID)] + cardIDs.map { .integer($0) }
        try db.run("UPDATE cards SET deck_id = ? WHERE id IN (\(placeholders))", values)
    }

    static func normalizeDeckName(_ name: String) -> String {
        name.components(separatedBy: Deck.separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: Deck.separator)
    }

    // MARK: - Counts

    /// Aggregated, limit-aware study counts for a deck (including subdecks).
    public func deckCounts(for deck: Deck, now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> DeckCounts {
        let clock = try dayClock()
        let startToday = clock.startEpoch(ofDay: clock.today(now: now))
        let endToday = clock.endOfTodayEpoch(now: now)
        let ids = try descendantDeckIDs(of: deck)
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let idValues = ids.map { SQLiteValue.integer($0) }
        let config = try self.config(for: deck)

        var counts = DeckCounts()

        counts.total = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM cards WHERE deck_id IN (\(placeholders))", idValues))
        counts.suspended = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM cards WHERE deck_id IN (\(placeholders)) AND suspended = 1", idValues))

        // New cards available today.
        let newTotal = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM cards WHERE deck_id IN (\(placeholders)) AND state = 0 AND suspended = 0 AND bury = 0",
            idValues))
        let newDone = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM revlog WHERE state_before = 0 AND reviewed_at >= ? AND reviewed_at <= ? " +
            "AND card_id IN (SELECT id FROM cards WHERE deck_id IN (\(placeholders)))",
            [.integer(startToday), .integer(now)] + idValues))
        counts.newCount = min(max(0, config.newPerDay - newDone), newTotal)

        // Learning / relearning due today.
        counts.learningCount = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM cards WHERE deck_id IN (\(placeholders)) AND state IN (1,3) " +
            "AND suspended = 0 AND bury = 0 AND due <= ?",
            idValues + [.integer(endToday)]))

        // Reviews due today.
        let reviewDue = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM cards WHERE deck_id IN (\(placeholders)) AND state = 2 " +
            "AND suspended = 0 AND bury = 0 AND due <= ?",
            idValues + [.integer(endToday)]))
        let reviewDone = Int(try db.scalarInt(
            "SELECT COUNT(*) FROM revlog WHERE state_before = 2 AND reviewed_at >= ? AND reviewed_at <= ? " +
            "AND card_id IN (SELECT id FROM cards WHERE deck_id IN (\(placeholders)))",
            [.integer(startToday), .integer(now)] + idValues))
        counts.reviewCount = min(max(0, config.reviewsPerDay - reviewDone), reviewDue)

        // Soonest next due among scheduled cards.
        let next = try db.query(
            "SELECT MIN(due) FROM cards WHERE deck_id IN (\(placeholders)) AND state IN (1,2,3) " +
            "AND suspended = 0 AND bury = 0 AND due > ?",
            idValues + [.integer(now)]) { $0.intOptional(0) }.first ?? nil
        counts.nextDue = next

        return counts
    }
}
