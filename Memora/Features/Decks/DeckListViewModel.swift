//
//  DeckListViewModel.swift
//  Memora
//

import Foundation
import SwiftUI

struct DeckNode: Identifiable, Hashable {
    var deck: Deck
    var counts: DeckCounts
    var depth: Int
    var hasChildren: Bool
    var id: Int64 { deck.id }
}

@MainActor
final class DeckListViewModel: ObservableObject {
    @Published var nodes: [DeckNode] = []
    @Published var totalDue = 0

    func load(_ store: MemoraStore) {
        do {
            let decks = try store.allDecks().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let names = Set(decks.map { $0.name })
            var result: [DeckNode] = []
            var due = 0
            for deck in decks {
                let counts = try store.deckCounts(for: deck)
                let hasChildren = names.contains { $0.hasPrefix(deck.name + Deck.separator) }
                result.append(DeckNode(deck: deck, counts: counts, depth: deck.depth, hasChildren: hasChildren))
                if deck.parentID == nil {
                    due += counts.newCount + counts.learningCount + counts.reviewCount
                }
            }
            self.nodes = result
            self.totalDue = due
        } catch {
            self.nodes = []
        }
    }

    func visibleNodes() -> [DeckNode] {
        // Hide nodes whose ancestor is collapsed.
        var collapsedPrefixes: [String] = []
        var visible: [DeckNode] = []
        for node in nodes {
            let hidden = collapsedPrefixes.contains { node.deck.name.hasPrefix($0) }
            if !hidden { visible.append(node) }
            if node.deck.collapsed {
                collapsedPrefixes.append(node.deck.name + Deck.separator)
            }
        }
        return visible
    }
}
