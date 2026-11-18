//
//  StudyViewModel.swift
//  Memora
//
//  Drives a study session: builds the queue dynamically (learning-due-now,
//  then an interleave of reviews and new cards within the deck's daily limits),
//  renders each card, applies the chosen scheduler on answer, writes the
//  review log, and supports undo of the last answer.
//

import Foundation
import SwiftUI

@MainActor
final class StudyViewModel: ObservableObject {
    struct Snapshot {
        var card: Card
        var logID: Int64
        var wasNew: Bool
        var wasReview: Bool
    }

    @Published var rendered: RenderedCard?
    @Published var showingAnswer = false
    @Published var finished = false
    @Published var previews: [Rating: NextInterval] = [:]
    @Published var newRemaining = 0
    @Published var reviewRemaining = 0
    @Published var learningCount = 0
    @Published var answeredThisSession = 0
    @Published var canUndo = false
    @Published var warnings: [String] = []
    @Published var deckName = ""
    @Published var waitingMessage: String?

    private var store: MemoraStore!
    private let deckID: Int64
    private var deckIDs: [Int64] = []
    private var config = DeckConfig.makeDefault()
    private var scheduler: ReviewScheduler!
    private var clock = DayClock(creationEpoch: 0, rolloverHour: 4)

    private(set) var currentCard: Card?
    private var currentNote: Note?
    private var newDone = 0
    private var reviewDone = 0
    private var answerShownAt = Date()
    private var undoStack: [Snapshot] = []

    init(deckID: Int64) {
        self.deckID = deckID
    }

    func configure(store: MemoraStore) {
        self.store = store
    }

    func start() {
        guard store != nil else { finished = true; return }
        do {
            guard let deck = try store.deck(id: deckID) else { finished = true; return }
            deckName = deck.leafName
            deckIDs = try store.descendantDeckIDs(of: deck)
            config = try store.config(for: deck)
            clock = try store.dayClock()
            scheduler = ReviewScheduler(config: config, dayClock: clock)
            let now = Int64(Date().timeIntervalSince1970)
            let startToday = clock.startEpoch(ofDay: clock.today(now: now))
            newDone = try store.newIntroducedToday(deckIDs: deckIDs, start: startToday, now: now)
            reviewDone = try store.reviewsDoneToday(deckIDs: deckIDs, start: startToday, now: now)
            loadNext()
        } catch { finished = true }
    }

    func loadNext() {
        do {
            let now = Int64(Date().timeIntervalSince1970)
            let endToday = clock.endOfTodayEpoch(now: now)
            refreshRemaining(now: now)

            // 1) Learning / relearning due now.
            if let card = try store.nextLearningCard(deckIDs: deckIDs, now: now) {
                try present(card)
                return
            }
            // 2) Interleave reviews and new cards.
            let reviewCard = reviewRemaining > 0 ? try store.nextReviewCard(deckIDs: deckIDs, endOfToday: endToday, order: config.reviewCardOrder) : nil
            let newCard = newRemaining > 0 ? try store.nextNewCard(deckIDs: deckIDs, order: config.newCardOrder) : nil

            let chosen: Card?
            if let r = reviewCard, let n = newCard {
                chosen = (answeredThisSession % 4 == 0) ? n : r
            } else {
                chosen = reviewCard ?? newCard
            }
            if let card = chosen {
                try present(card)
                return
            }
            // 3) Nothing available now — is something in learning due later today?
            if let soon = try store.nextLearningCard(deckIDs: deckIDs, now: endToday), soon.due > now {
                waitingMessage = "Has terminado las tarjetas disponibles ahora. Quedan \(learningCount) en aprendizaje; vuelve en unos minutos."
            }
            finished = true
        } catch { finished = true }
    }

    private func present(_ card: Card) throws {
        guard let note = try store.note(id: card.noteID),
              let nt = try store.notetype(id: note.notetypeID) else {
            // Skip a broken card rather than crashing the session.
            currentCard = card
            try? advancePastBrokenCard(card)
            return
        }
        currentCard = card
        currentNote = note
        let rc = CardRenderer.render(card: card, note: note, notetype: nt, deckName: deckName)
        rendered = rc
        warnings = rc.warnings.map { $0.message }
        previews = scheduler.previews(for: card)
        showingAnswer = false
        answerShownAt = Date()
    }

    private func advancePastBrokenCard(_ card: Card) throws {
        // Suspend an unrenderable card so the queue can continue.
        try store.setSuspended(true, cardIDs: [card.id])
        loadNext()
    }

    func reveal() { showingAnswer = true }

    func answer(_ rating: Rating) {
        guard let card = currentCard else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let elapsedMS = min(120_000, Int(Date().timeIntervalSince(answerShownAt) * 1000))
        let wasNew = card.state == .new
        let wasReview = card.state == .review
        let result = scheduler.apply(rating: rating, to: card, now: now,
                                     nowMillis: store.nextID(), timeMS: elapsedMS)
        do {
            try store.commit(result, leechAction: config.leechAction)
            undoStack.append(Snapshot(card: card, logID: result.log.id, wasNew: wasNew, wasReview: wasReview))
            if undoStack.count > 50 { undoStack.removeFirst() }
            canUndo = true
            if wasNew { newDone += 1 }
            if wasReview { reviewDone += 1 }
            answeredThisSession += 1
            loadNext()
        } catch { store_presentError(error) }
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        do {
            try store.deleteRevlog(id: snap.logID)
            try store.saveCard(snap.card)
            if snap.wasNew { newDone = max(0, newDone - 1) }
            if snap.wasReview { reviewDone = max(0, reviewDone - 1) }
            answeredThisSession = max(0, answeredThisSession - 1)
            canUndo = !undoStack.isEmpty
            finished = false
            waitingMessage = nil
            try present(snap.card)
        } catch { store_presentError(error) }
    }

    private func refreshRemaining(now: Int64) {
        newRemaining = max(0, config.newPerDay - newDone)
        reviewRemaining = max(0, config.reviewsPerDay - reviewDone)
        learningCount = (try? Int(store.db.scalarInt(
            "SELECT COUNT(*) FROM cards WHERE deck_id IN (\(deckIDs.map { _ in "?" }.joined(separator: ","))) AND state IN (1,3) AND suspended = 0 AND bury = 0",
            deckIDs.map { .integer($0) }))) ?? 0
    }

    // Surface errors through the shared environment via a notification closure.
    var onError: ((Error) -> Void)?
    private func store_presentError(_ error: Error) { onError?(error) }

    func intervalLabel(for rating: Rating) -> String {
        guard let interval = previews[rating] else { return "" }
        return IntervalFormatter.short(interval)
    }
}
