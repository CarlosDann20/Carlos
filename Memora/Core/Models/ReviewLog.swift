//
//  ReviewLog.swift
//  Memora
//
//  One row per review action. This is the source of truth for statistics,
//  for FSRS optimisation input, and for the "undo" feature.
//

import Foundation

public enum ReviewKind: Int, Codable, Sendable {
    case learn = 0
    case review = 1
    case relearn = 2
    case cram = 3       // filtered / custom study
    case manual = 4     // reschedule / set state
}

public struct ReviewLog: Identifiable, Sendable, Hashable {
    /// Epoch milliseconds, also the primary key (matches Anki revlog.id).
    public var id: Int64
    public var cardID: Int64
    public var rating: Rating
    /// Interval assigned by this review (days; negative seconds in Anki for
    /// sub-day — Memora stores days, with 0 for intra-day steps).
    public var interval: Int
    /// Previous interval before this review.
    public var lastInterval: Int
    /// Ease factor at review time (permille) for SM-2, else 0.
    public var easeFactor: Int
    /// Memory state snapshot (FSRS), if applicable.
    public var stability: Double?
    public var difficulty: Double?
    /// State before the review, for undo and stats.
    public var stateBefore: CardState
    public var kind: ReviewKind
    /// Time spent in milliseconds.
    public var timeMS: Int
    /// When the review happened, epoch seconds.
    public var reviewedAt: Int64

    public init(id: Int64, cardID: Int64, rating: Rating, interval: Int,
                lastInterval: Int, easeFactor: Int, stability: Double?,
                difficulty: Double?, stateBefore: CardState, kind: ReviewKind,
                timeMS: Int, reviewedAt: Int64) {
        self.id = id
        self.cardID = cardID
        self.rating = rating
        self.interval = interval
        self.lastInterval = lastInterval
        self.easeFactor = easeFactor
        self.stability = stability
        self.difficulty = difficulty
        self.stateBefore = stateBefore
        self.kind = kind
        self.timeMS = timeMS
        self.reviewedAt = reviewedAt
    }
}
