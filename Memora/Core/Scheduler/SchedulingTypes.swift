//
//  SchedulingTypes.swift
//  Memora
//
//  Shared vocabulary for both schedulers (FSRS and SM-2). A scheduler is a
//  pure function from (card, rating, elapsed time) to an outcome; it never
//  touches the database. The ReviewScheduler applies the outcome.
//

import Foundation

/// The next interval, either a sub-day step (seconds) or a day count.
public enum NextInterval: Sendable, Hashable {
    case seconds(Int)
    case days(Int)

    /// Approximate seconds, for sorting / comparisons.
    public var approxSeconds: Int {
        switch self {
        case .seconds(let s): return s
        case .days(let d): return d * 86_400
        }
    }

    /// Day count for logging (0 for sub-day steps).
    public var dayCount: Int {
        switch self {
        case .seconds: return 0
        case .days(let d): return d
        }
    }
}

/// The full result of grading a card, without persistence side effects.
public struct SchedulingOutcome: Sendable, Hashable {
    public var state: CardState
    public var learningStep: Int
    public var stability: Double?
    public var difficulty: Double?
    public var easeFactor: Int
    public var interval: NextInterval
    public var reps: Int
    public var lapses: Int

    public init(state: CardState, learningStep: Int, stability: Double?, difficulty: Double?,
                easeFactor: Int, interval: NextInterval, reps: Int, lapses: Int) {
        self.state = state
        self.learningStep = learningStep
        self.stability = stability
        self.difficulty = difficulty
        self.easeFactor = easeFactor
        self.interval = interval
        self.reps = reps
        self.lapses = lapses
    }
}

public protocol CardScheduler: Sendable {
    var kind: SchedulerKind { get }
    /// Compute the outcome for one rating. `elapsedDays` is whole days since
    /// the last review (0 if never reviewed or same day). Fuzz, if any, is
    /// applied internally and should be disabled for deterministic previews.
    func outcome(for card: Card, rating: Rating, elapsedDays: Int, applyFuzz: Bool) -> SchedulingOutcome
}

/// Human-readable interval label for the answer buttons, e.g. "10 min", "3 d",
/// "1,2 mes", "2 a".
public enum IntervalFormatter {
    public static func short(_ interval: NextInterval) -> String {
        switch interval {
        case .seconds(let s):
            if s < 60 { return "\(max(1, s)) s" }
            let minutes = Int((Double(s) / 60).rounded())
            if minutes < 60 { return "\(minutes) min" }
            let hours = Double(s) / 3600
            return String(format: "%.1f h", hours)
        case .days(let d):
            if d < 30 { return "\(d) d" }
            if d < 365 {
                let months = Double(d) / 30.4
                return String(format: "%.1f mes", months)
            }
            let years = Double(d) / 365.0
            return String(format: "%.1f a", years)
        }
    }
}
