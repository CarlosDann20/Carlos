//
//  Card.swift
//  Memora
//
//  A single studyable card. Carries both FSRS memory state (stability /
//  difficulty) and the SM-2 ease factor so a deck can switch schedulers
//  without losing data.
//

import Foundation

public struct Card: Identifiable, Sendable, Hashable {
    public var id: Int64
    public var noteID: Int64
    public var deckID: Int64
    /// Which template of the note type produced this card (Anki `ord`). For
    /// cloze notes this is the cloze number minus one.
    public var templateOrd: Int

    public var state: CardState
    /// Next-due time, epoch seconds. For `new` cards this is unused (ordering
    /// uses `position`).
    public var due: Int64
    /// Ordering index for new cards.
    public var position: Int64
    /// Current interval in days (review state).
    public var intervalDays: Int
    public var reps: Int
    public var lapses: Int
    /// Zero-based index into the deck's (re)learning steps.
    public var learningStep: Int

    // FSRS memory state (nil until first review for new cards).
    public var stability: Double?
    public var difficulty: Double?

    // SM-2 ease factor, stored in permille like Anki (2500 == 2.5).
    public var easeFactor: Int

    public var lastReview: Int64?
    public var suspended: Bool
    public var bury: BuryState
    public var favorite: Bool
    /// Anki coloured flag (0 = none, 1...7).
    public var flags: Int

    // Filtered / custom-study bookkeeping (Anki odue / odid).
    public var originalDue: Int64
    public var originalDeckID: Int64

    public var created: Int64
    public var modified: Int64

    public init(id: Int64, noteID: Int64, deckID: Int64, templateOrd: Int,
                state: CardState = .new, due: Int64 = 0, position: Int64 = 0,
                intervalDays: Int = 0, reps: Int = 0, lapses: Int = 0,
                learningStep: Int = 0, stability: Double? = nil, difficulty: Double? = nil,
                easeFactor: Int = 2500, lastReview: Int64? = nil,
                suspended: Bool = false, bury: BuryState = .none,
                favorite: Bool = false, flags: Int = 0,
                originalDue: Int64 = 0, originalDeckID: Int64 = 0,
                created: Int64 = 0, modified: Int64 = 0) {
        self.id = id
        self.noteID = noteID
        self.deckID = deckID
        self.templateOrd = templateOrd
        self.state = state
        self.due = due
        self.position = position
        self.intervalDays = intervalDays
        self.reps = reps
        self.lapses = lapses
        self.learningStep = learningStep
        self.stability = stability
        self.difficulty = difficulty
        self.easeFactor = easeFactor
        self.lastReview = lastReview
        self.suspended = suspended
        self.bury = bury
        self.favorite = favorite
        self.flags = flags
        self.originalDue = originalDue
        self.originalDeckID = originalDeckID
        self.created = created
        self.modified = modified
    }

    public var isBuried: Bool { bury != .none }
    public var isDueForStudy: Bool { !suspended && !isBuried }
}
