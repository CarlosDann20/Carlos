//
//  ReviewScheduler.swift
//  Memora
//
//  Applies a chosen scheduler (FSRS or SM-2) to a card: computes the concrete
//  next-due time, the updated card, and a review-log row. Also produces the
//  interval previews shown on the Again/Hard/Good/Easy buttons.
//
//  This type is pure (no database access) so it can be unit-tested directly.
//

import Foundation

public struct ReviewResult: Sendable {
    public var card: Card
    public var log: ReviewLog
    public var becameLeech: Bool
}

public struct ReviewScheduler: Sendable {
    public let config: DeckConfig
    public let dayClock: DayClock
    private let engine: CardScheduler

    public init(config: DeckConfig, dayClock: DayClock) {
        self.config = config
        self.dayClock = dayClock
        switch config.scheduler {
        case .fsrs: self.engine = FSRSScheduler(config: config)
        case .sm2: self.engine = SM2Scheduler(config: config)
        }
    }

    /// Whole wall-clock days since the last review (matches the FSRS reference).
    private func elapsedDays(for card: Card, now: Int64) -> Int {
        guard let last = card.lastReview else { return 0 }
        return max(0, Int((now - last) / 86_400))
    }

    /// Unfuzzed interval previews for the four buttons.
    public func previews(for card: Card, now: Int64 = Int64(Date().timeIntervalSince1970)) -> [Rating: NextInterval] {
        let elapsed = elapsedDays(for: card, now: now)
        var result: [Rating: NextInterval] = [:]
        for rating in Rating.allCases {
            result[rating] = engine.outcome(for: card, rating: rating, elapsedDays: elapsed, applyFuzz: false).interval
        }
        return result
    }

    /// Apply a rating, returning the updated card + a review log.
    public func apply(rating: Rating, to card: Card, now: Int64 = Int64(Date().timeIntervalSince1970),
                      nowMillis: Int64? = nil, timeMS: Int = 0) -> ReviewResult {
        let elapsed = elapsedDays(for: card, now: now)
        let outcome = engine.outcome(for: card, rating: rating, elapsedDays: elapsed, applyFuzz: true)

        var updated = card
        updated.state = outcome.state
        updated.learningStep = outcome.learningStep
        if let s = outcome.stability { updated.stability = s }
        if let d = outcome.difficulty { updated.difficulty = d }
        updated.easeFactor = outcome.easeFactor
        updated.reps = outcome.reps
        updated.lapses = outcome.lapses

        switch outcome.interval {
        case .seconds(let s):
            updated.intervalDays = 0
            updated.due = now + Int64(s)
        case .days(let d):
            updated.intervalDays = d
            let dueDay = dayClock.today(now: now) + d
            updated.due = dayClock.startEpoch(ofDay: dueDay)
        }
        updated.lastReview = now
        updated.modified = now

        // Leech handling.
        var becameLeech = false
        if outcome.lapses > card.lapses, isLeech(lapses: outcome.lapses) {
            becameLeech = true
            if config.leechAction == .suspend {
                updated.suspended = true
            }
        }

        let kind: ReviewKind
        switch card.state {
        case .new, .learning: kind = .learn
        case .review: kind = (rating == .again) ? .relearn : .review
        case .relearning: kind = .relearn
        }

        let logID = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        let log = ReviewLog(id: logID, cardID: card.id, rating: rating,
                            interval: outcome.interval.dayCount, lastInterval: card.intervalDays,
                            easeFactor: outcome.easeFactor, stability: outcome.stability,
                            difficulty: outcome.difficulty, stateBefore: card.state,
                            kind: kind, timeMS: timeMS, reviewedAt: now)

        return ReviewResult(card: updated, log: log, becameLeech: becameLeech)
    }

    /// Anki-style leech detection: first at the threshold, then on every half.
    private func isLeech(lapses: Int) -> Bool {
        let threshold = config.leechThreshold
        guard threshold > 0, lapses >= threshold else { return false }
        let half = max(1, threshold / 2)
        return (lapses - threshold) % half == 0
    }
}
