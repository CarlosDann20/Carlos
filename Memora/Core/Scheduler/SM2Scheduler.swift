//
//  SM2Scheduler.swift
//  Memora
//
//  A faithful implementation of the SuperMemo-2 (SM-2) algorithm, offered as
//  the classic alternative to FSRS.
//
//  The core of SM-2 is the easiness-factor update
//      EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
//  with EF floored at 1.3, and the repetition-interval progression
//      I(1) = 1, I(2) = 6, I(n) = round(I(n-1) * EF).
//  (P.A. Wozniak, "Optimization of learning", 1990.)
//
//  Around that core we add Anki-style practicalities: configurable
//  (re)learning steps for sub-day scheduling, an interval modifier, an easy
//  bonus, a hard-interval multiplier and a configurable post-lapse interval.
//  The easiness factor is stored in permille (2500 == EF 2.5), matching Anki.
//

import Foundation

public struct SM2Scheduler: CardScheduler {
    public let kind: SchedulerKind = .sm2

    public let learningStepsSeconds: [Int]
    public let relearningStepsSeconds: [Int]
    public let startingEase: Int
    public let easyBonus: Double
    public let intervalModifier: Double
    public let hardIntervalMultiplier: Double
    public let lapseNewIntervalPercent: Double
    public let minimumIntervalDays: Int
    public let maximumIntervalDays: Int

    // Anki-equivalent graduation defaults.
    public let graduatingIntervalDays = 1
    public let easyIntervalDays = 4
    private let minEase = 1300

    public init(config: DeckConfig) {
        self.learningStepsSeconds = config.learningStepsMinutes.map { Int(($0 * 60).rounded()) }
        self.relearningStepsSeconds = config.relearningStepsMinutes.map { Int(($0 * 60).rounded()) }
        self.startingEase = config.startingEase
        self.easyBonus = config.easyBonus
        self.intervalModifier = config.intervalModifier
        self.hardIntervalMultiplier = config.hardIntervalMultiplier
        self.lapseNewIntervalPercent = config.lapseNewIntervalPercent
        self.minimumIntervalDays = max(1, config.minimumIntervalDays)
        self.maximumIntervalDays = config.maximumIntervalDays
    }

    public func outcome(for card: Card, rating: Rating, elapsedDays: Int, applyFuzz: Bool) -> SchedulingOutcome {
        var state = card.state
        var step = card.learningStep
        var ease = card.easeFactor == 0 ? startingEase : card.easeFactor
        var intervalDays = card.intervalDays
        let reps = card.reps + 1
        var lapses = card.lapses
        var interval: NextInterval

        switch card.state {
        case .new, .learning:
            let steps = learningStepsSeconds
            switch rating {
            case .again:
                state = .learning
                step = 0
                interval = stepInterval(steps, 0)
            case .hard:
                state = .learning
                interval = hardStepInterval(steps: steps, step: step)
            case .good:
                if steps.isEmpty || step + 1 >= steps.count {
                    state = .review
                    step = 0
                    ease = card.easeFactor == 0 ? startingEase : card.easeFactor
                    intervalDays = clampInterval(graduatingIntervalDays)
                    interval = .days(intervalDays)
                } else {
                    state = .learning
                    step += 1
                    interval = stepInterval(steps, step)
                }
            case .easy:
                state = .review
                step = 0
                ease = card.easeFactor == 0 ? startingEase : card.easeFactor
                intervalDays = clampInterval(easyIntervalDays)
                interval = .days(intervalDays)
            }

        case .review:
            ease = updatedEase(ease, rating: rating)
            switch rating {
            case .again:
                lapses += 1
                let post = max(minimumIntervalDays, Int((Double(card.intervalDays) * lapseNewIntervalPercent).rounded()))
                intervalDays = post
                if relearningStepsSeconds.isEmpty {
                    state = .review
                    interval = .days(clampInterval(post))
                } else {
                    state = .relearning
                    step = 0
                    interval = stepInterval(relearningStepsSeconds, 0)
                }
            case .hard:
                intervalDays = clampInterval(grow(card.intervalDays, factor: hardIntervalMultiplier))
                interval = .days(intervalDays)
            case .good:
                let efFactor = Double(ease) / 1000.0
                intervalDays = clampInterval(grow(card.intervalDays, factor: efFactor))
                interval = .days(intervalDays)
            case .easy:
                let efFactor = Double(ease) / 1000.0
                intervalDays = clampInterval(grow(card.intervalDays, factor: efFactor * easyBonus))
                interval = .days(intervalDays)
            }

        case .relearning:
            let steps = relearningStepsSeconds
            switch rating {
            case .again:
                state = .relearning
                step = 0
                interval = stepInterval(steps, 0)
            case .hard:
                state = .relearning
                interval = hardStepInterval(steps: steps, step: step)
            case .good, .easy:
                if steps.isEmpty || step + 1 >= steps.count || rating == .easy {
                    state = .review
                    step = 0
                    intervalDays = clampInterval(max(minimumIntervalDays, card.intervalDays))
                    interval = .days(intervalDays)
                } else {
                    state = .relearning
                    step += 1
                    interval = stepInterval(steps, step)
                }
            }
        }

        return SchedulingOutcome(state: state, learningStep: step,
                                 stability: nil, difficulty: nil,
                                 easeFactor: ease, interval: interval,
                                 reps: reps, lapses: lapses)
    }

    // MARK: - Helpers

    /// SM-2 easiness-factor update using the canonical quality formula.
    private func updatedEase(_ ease: Int, rating: Rating) -> Int {
        let q: Double
        switch rating {
        case .again: q = 1
        case .hard: q = 3
        case .good: q = 4
        case .easy: q = 5
        }
        var ef = Double(ease) / 1000.0
        ef += 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
        let permille = Int((ef * 1000).rounded())
        return max(minEase, permille)
    }

    private func grow(_ previous: Int, factor: Double) -> Int {
        let base = max(previous, 1)
        let grown = Int((Double(base) * factor * intervalModifier).rounded())
        return max(grown, base + 1)
    }

    private func clampInterval(_ days: Int) -> Int {
        min(max(days, minimumIntervalDays), maximumIntervalDays)
    }

    private func stepInterval(_ steps: [Int], _ index: Int) -> NextInterval {
        guard !steps.isEmpty else { return .days(clampInterval(graduatingIntervalDays)) }
        let i = min(max(0, index), steps.count - 1)
        return .seconds(steps[i])
    }

    private func hardStepInterval(steps: [Int], step: Int) -> NextInterval {
        if step == 0 && steps.count == 1 {
            return .seconds(Int(Double(steps[0]) * 1.5))
        } else if step == 0 && steps.count >= 2 {
            return .seconds((steps[0] + steps[1]) / 2)
        } else if step < steps.count {
            return .seconds(steps[step])
        } else {
            return .seconds(steps.last ?? 600)
        }
    }
}
