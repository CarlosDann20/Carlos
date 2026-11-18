//
//  Deck.swift
//  Memora
//
//  A deck (or subdeck). Hierarchy is encoded both in the full `name`
//  ("Spanish::Verbs::Irregular", matching Anki) and in `parentID` for fast
//  tree queries.
//

import Foundation

public struct Deck: Identifiable, Sendable, Hashable {
    public var id: Int64
    /// Full "::"-separated name.
    public var name: String
    public var parentID: Int64?
    public var configID: Int64
    public var collapsed: Bool
    /// A filtered/custom-study deck (Anki "dyn" deck).
    public var isFiltered: Bool
    public var created: Int64
    public var modified: Int64

    public init(id: Int64, name: String, parentID: Int64? = nil, configID: Int64 = 1,
                collapsed: Bool = false, isFiltered: Bool = false,
                created: Int64 = 0, modified: Int64 = 0) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.configID = configID
        self.collapsed = collapsed
        self.isFiltered = isFiltered
        self.created = created
        self.modified = modified
    }

    public static let separator = "::"

    /// The last path component, e.g. "Irregular".
    public var leafName: String {
        name.components(separatedBy: Deck.separator).last ?? name
    }

    /// Depth in the tree (0 for a top-level deck).
    public var depth: Int {
        name.components(separatedBy: Deck.separator).count - 1
    }

    public var parentName: String? {
        var parts = name.components(separatedBy: Deck.separator)
        guard parts.count > 1 else { return nil }
        parts.removeLast()
        return parts.joined(separator: Deck.separator)
    }
}

/// Aggregate study counts for a deck, used to render the deck list.
public struct DeckCounts: Sendable, Hashable {
    public var newCount: Int = 0
    public var learningCount: Int = 0
    public var reviewCount: Int = 0
    public var total: Int = 0
    public var suspended: Int = 0
    /// Soonest next-due time among scheduled cards, epoch seconds.
    public var nextDue: Int64?

    public init() {}
}
