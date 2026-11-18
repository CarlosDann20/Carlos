//
//  MemoraStore+Search.swift
//  Memora
//
//  The card browser's query engine. Joins cards + notes, applies text / tag /
//  deck / state filters, and sorts — designed to stay responsive on large
//  collections via indexed columns and LIMIT/OFFSET paging.
//

import Foundation

public enum CardSortField: String, CaseIterable, Sendable {
    case sortField, due, interval, created, modified, reps, lapses, state

    public var displayName: String {
        switch self {
        case .sortField: return "Alfabético"
        case .due: return "Fecha de repaso"
        case .interval: return "Intervalo"
        case .created: return "Creación"
        case .modified: return "Modificación"
        case .reps: return "Repasos"
        case .lapses: return "Olvidos"
        case .state: return "Estado"
        }
    }

    var column: String {
        switch self {
        case .sortField: return "n.sfld"
        case .due: return "c.due"
        case .interval: return "c.ivl"
        case .created: return "c.created"
        case .modified: return "c.modified"
        case .reps: return "c.reps"
        case .lapses: return "c.lapses"
        case .state: return "c.state"
        }
    }
}

public struct CardBrowseFilter: Sendable {
    public var deckIDs: [Int64]?       // nil = all decks
    public var text: String = ""
    public var tag: String?            // filter by a single tag
    public var favoritesOnly = false
    public var suspendedOnly = false
    public var state: CardState?
    public var sort: CardSortField = .sortField
    public var ascending = true
    public var limit = 200
    public var offset = 0

    public init() {}
}

public struct CardBrowseRow: Identifiable, Sendable, Hashable {
    public var id: Int64
    public var noteID: Int64
    public var deckID: Int64
    public var question: String      // stripped sort field
    public var answerPreview: String // stripped remaining fields
    public var tags: [String]
    public var state: CardState
    public var due: Int64
    public var intervalDays: Int
    public var favorite: Bool
    public var suspended: Bool
    public var flags: Int
}

extension MemoraStore {

    public func browse(_ filter: CardBrowseFilter) throws -> [CardBrowseRow] {
        var sql = """
        SELECT c.id, c.note_id, c.deck_id, n.sfld, n.flds, n.tags, c.state, c.due, c.ivl,
               c.favorite, c.suspended, c.flags
        FROM cards c JOIN notes n ON n.id = c.note_id
        """
        var clauses: [String] = []
        var values: [SQLiteValue] = []

        if let deckIDs = filter.deckIDs, !deckIDs.isEmpty {
            clauses.append("c.deck_id IN (\(deckIDs.map { _ in "?" }.joined(separator: ",")))")
            values.append(contentsOf: deckIDs.map { .integer($0) })
        }
        let text = filter.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !text.isEmpty {
            clauses.append("n.search_text LIKE ? ESCAPE '\\'")
            values.append(.text("%\(escapeLike(text))%"))
        }
        if let tag = filter.tag, !tag.isEmpty {
            clauses.append("(' ' || n.tags || ' ') LIKE ? ESCAPE '\\'")
            values.append(.text("% \(escapeLike(tag)) %"))
        }
        if filter.favoritesOnly { clauses.append("c.favorite = 1") }
        if filter.suspendedOnly { clauses.append("c.suspended = 1") }
        if let state = filter.state { clauses.append("c.state = \(state.rawValue)") }

        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY \(filter.sort.column) COLLATE NOCASE \(filter.ascending ? "ASC" : "DESC")"
        sql += " LIMIT ? OFFSET ?"
        values.append(.integer(Int64(filter.limit)))
        values.append(.integer(Int64(filter.offset)))

        return try db.query(sql, values) { row in
            let fields = Note.splitFields(row.string(4))
            let answer = fields.dropFirst().map { TextStripping.stripHTML($0) }.filter { !$0.isEmpty }.joined(separator: " · ")
            let tagStr = row.string(5)
            let tags = tagStr.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            return CardBrowseRow(id: row.int(0), noteID: row.int(1), deckID: row.int(2),
                                 question: row.string(3), answerPreview: answer, tags: tags,
                                 state: CardState(rawValue: Int(row.int(6))) ?? .new,
                                 due: row.int(7), intervalDays: Int(row.int(8)),
                                 favorite: row.int(9) != 0, suspended: row.int(10) != 0,
                                 flags: Int(row.int(11)))
        }
    }

    public func browseCount(_ filter: CardBrowseFilter) throws -> Int {
        var sql = "SELECT COUNT(*) FROM cards c JOIN notes n ON n.id = c.note_id"
        var clauses: [String] = []
        var values: [SQLiteValue] = []
        if let deckIDs = filter.deckIDs, !deckIDs.isEmpty {
            clauses.append("c.deck_id IN (\(deckIDs.map { _ in "?" }.joined(separator: ",")))")
            values.append(contentsOf: deckIDs.map { .integer($0) })
        }
        let text = filter.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !text.isEmpty { clauses.append("n.search_text LIKE ? ESCAPE '\\'"); values.append(.text("%\(escapeLike(text))%")) }
        if let tag = filter.tag, !tag.isEmpty { clauses.append("(' ' || n.tags || ' ') LIKE ? ESCAPE '\\'"); values.append(.text("% \(escapeLike(tag)) %")) }
        if filter.favoritesOnly { clauses.append("c.favorite = 1") }
        if filter.suspendedOnly { clauses.append("c.suspended = 1") }
        if let state = filter.state { clauses.append("c.state = \(state.rawValue)") }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        return Int(try db.scalarInt(sql, values))
    }

    private func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }
}
