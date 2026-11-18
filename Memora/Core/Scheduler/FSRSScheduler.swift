//
//  FSRSScheduler.swift
//  Memora
//
//  A faithful Swift port of FSRS-6 (Free Spaced Repetition Scheduler).
//
//  The formulas, default parameters, learning-step state machine and interval
//  fuzzing below mirror the reference implementation `py-fsrs`
//  (https://github.com/open-spaced-repetition/py-fsrs, MIT License) one-to-one,
//  so that Memora schedules cards identically to the reference and so that
//  review history imported from Anki (which also uses FSRS) stays consistent.
//
//  FSRS algorithm: Jarrett Ye and the Open Spaced Repetition contributors.
//  See docs/LICENSES.md for attribution.
//

import Foundation

public struct FSRSScheduler: CardScheduler {
    public let kind: SchedulerKind = .fsrs

    // 21 model weights (FSRS-6). Index 20 is the learnable decay.
    public let parameters: [Double]
    public let desiredRetention: Double
    public let learningStepsSeconds: [Int]
    public let relearningStepsSeconds: [Int]
    public let maximumIntervalDays: Int
    public let enableFuzz: Bool

    private let decay: Double
    private let factor: Double

    public static let defaultDecay = 0.1542
    public static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, defaultDecay
    ]

    private static let stabilityMin = 0.001
    private static let minDifficulty = 1.0
    private static let maxDifficulty = 10.0

    public init(parameters: [Double] = FSRSScheduler.defaultParameters,
                desiredRetention: Double = 0.9,
                learningStepsMinutes: [Double] = [1, 10],
                relearningStepsMinutes: [Double] = [10],
                maximumIntervalDays: Int = 36500,
                enableFuzz: Bool = true) {
        self.parameters = parameters.count == 21 ? parameters : FSRSScheduler.defaultParameters
        self.desiredRetention = desiredRetention
        self.learningStepsSeconds = learningStepsMinutes.map { Int(($0 * 60).rounded()) }
        self.relearningStepsSeconds = relearningStepsMinutes.map { Int(($0 * 60).rounded()) }
        self.maximumIntervalDays = maximumIntervalDays
        self.enableFuzz = enableFuzz
        self.decay = -self.parameters[20]
        self.factor = pow(0.9, 1.0 / self.decay) - 1.0
    }

    public init(config: DeckConfig) {
        self.init(parameters: config.fsrsParameters,
                  desiredRetention: config.desiredRetention,
                  learningStepsMinutes: config.learningStepsMinutes,
                  relearningStepsMinutes: config.relearningStepsMinutes,
                  maximumIntervalDays: config.maximumIntervalDays,
                  enableFuzz: config.enableFuzz)
    }

    // MARK: - Public API

    public func outcome(for card: Card, rating: Rating, elapsedDays: Int, applyFuzz: Bool) -> SchedulingOutcome {
        let g = rating.rawValue
        var state = card.state
        var step = card.learningStep
        var stability = card.stability
        var difficulty = card.difficulty
        let sameDay = card.lastReview != nil && elapsedDays < 1

        var interval: NextInterval = .seconds(60)

        switch card.state {
        case .new, .learning:
            // Update memory state.
            if stability == nil || difficulty == nil {
                stability = initialStability(g)
                difficulty = initialDifficulty(g, clamp: true)
            } else if sameDay {
                stability = shortTermStability(stability!, g)
                difficulty = nextDifficulty(difficulty!, g)
            } else {
                let r = retrievability(elapsedDays: elapsedDays, stability: stability!)
                stability = nextStability(difficulty: difficulty!, stability: stability!, retrievability: r, rating: g)
                difficulty = nextDifficulty(difficulty!, g)
            }

            let steps = learningStepsSeconds
            if steps.isEmpty || (step >= steps.count && g >= Rating.hard.rawValue) {
                state = .review
                step = 0
                interval = .days(nextIntervalDays(stability: stability!))
            } else {
                // First review of a `.new` card that stays in the learning
                // phase transitions it to `.learning`.
                state = .learning
                switch rating {
                case .again:
                    step = 0
                    interval = .seconds(steps[0])
                case .hard:
                    interval = hardStepInterval(steps: steps, step: step)
                case .good:
                    if step + 1 == steps.count {
                        state = .review
                        step = 0
                        interval = .days(nextIntervalDays(stability: stability!))
                    } else {
                        step += 1
                        interval = .seconds(steps[step])
                    }
                case .easy:
                    state = .review
                    step = 0
                    interval = .days(nextIntervalDays(stability: stability!))
                }
            }

        case .review:
            if sameDay {
                stability = shortTermStability(stability ?? initialStability(g), g)
            } else {
                let base = stability ?? initialStability(g)
                let r = retrievability(elapsedDays: elapsedDays, stability: base)
                stability = nextStability(difficulty: difficulty ?? initialDifficulty(g, clamp: true),
                                          stability: base, retrievability: r, rating: g)
            }
            difficulty = nextDifficulty(difficulty ?? initialDifficulty(g, clamp: true), g)

            switch rating {
            case .again:
                if relearningStepsSeconds.isEmpty {
                    interval = .days(nextIntervalDays(stability: stability!))
                } else {
                    state = .relearning
                    step = 0
                    interval = .seconds(relearningStepsSeconds[0])
                }
            case .hard, .good, .easy:
                interval = .days(nextIntervalDays(stability: stability!))
            }

        case .relearning:
            if sameDay {
                stability = shortTermStability(stability ?? initialStability(g), g)
                difficulty = nextDifficulty(difficulty ?? initialDifficulty(g, clamp: true), g)
            } else {
                let base = stability ?? initialStability(g)
                let r = retrievability(elapsedDays: elapsedDays, stability: base)
                stability = nextStability(difficulty: difficulty ?? initialDifficulty(g, clamp: true),
                                          stability: base, retrievability: r, rating: g)
                difficulty = nextDifficulty(difficulty ?? initialDifficulty(g, clamp: true), g)
            }

            let steps = relearningStepsSeconds
            if steps.isEmpty || (step >= steps.count && g >= Rating.hard.rawValue) {
                state = .review
                step = 0
                interval = .days(nextIntervalDays(stability: stability!))
            } else {
                switch rating {
                case .again:
                    step = 0
                    interval = .seconds(steps[0])
                case .hard:
                    interval = hardStepInterval(steps: steps, step: step)
                case .good:
                    if step + 1 == steps.count {
                        state = .review
                        step = 0
                        interval = .days(nextIntervalDays(stability: stability!))
                    } else {
                        step += 1
                        interval = .seconds(steps[step])
                    }
                case .easy:
                    state = .review
                    step = 0
                    interval = .days(nextIntervalDays(stability: stability!))
                }
            }
        }

        // Fuzz only applies to review-state day intervals.
        if applyFuzz && enableFuzz && state == .review, case .days(let d) = interval {
            interval = .days(fuzzedInterval(days: d))
        }

        let reps = card.reps + 1
        let lapses = (card.state == .review && rating == .again) ? card.lapses + 1 : card.lapses

        return SchedulingOutcome(state: state, learningStep: step,
                                 stability: stability, difficulty: difficulty,
                                 easeFactor: card.easeFactor, interval: interval,
                                 reps: reps, lapses: lapses)
    }

    /// Predicted recall probability after `elapsedDays` with the given stability.
    public func retrievability(elapsedDays: Int, stability: Double) -> Double {
        let t = Double(max(0, elapsedDays))
        return pow(1 + factor * t / stability, decay)
    }

    // MARK: - Core formulas (mirror py-fsrs)

    private func clampStability(_ s: Double) -> Double { max(s, FSRSScheduler.stabilityMin) }
    private func clampDifficulty(_ d: Double) -> Double {
        min(max(d, FSRSScheduler.minDifficulty), FSRSScheduler.maxDifficulty)
    }

    private func initialStability(_ g: Int) -> Double {
        clampStability(parameters[g - 1])
    }

    private func initialDifficulty(_ g: Int, clamp: Bool) -> Double {
        let d = parameters[4] - exp(parameters[5] * Double(g - 1)) + 1
        return clamp ? clampDifficulty(d) : d
    }

    private func nextIntervalDays(stability: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1.0 / decay) - 1.0)
        var ivl = Int(raw.rounded())
        ivl = max(ivl, 1)
        ivl = min(ivl, maximumIntervalDays)
        return ivl
    }

    private func shortTermStability(_ stability: Double, _ g: Int) -> Double {
        var inc = exp(parameters[17] * (Double(g) - 3 + parameters[18])) * pow(stability, -parameters[19])
        if g >= Rating.hard.rawValue {
            inc = max(inc, 1.0)
        }
        return clampStability(stability * inc)
    }

    private func nextDifficulty(_ difficulty: Double, _ g: Int) -> Double {
        let arg1 = initialDifficulty(Rating.easy.rawValue, clamp: false)
        let deltaD = -(parameters[6] * Double(g - 3))
        let damped = (10.0 - difficulty) * deltaD / 9.0
        let arg2 = difficulty + damped
        let next = parameters[7] * arg1 + (1 - parameters[7]) * arg2
        return clampDifficulty(next)
    }

    private func nextStability(difficulty: Double, stability: Double, retrievability r: Double, rating g: Int) -> Double {
        let s: Double
        if g == Rating.again.rawValue {
            s = forgetStability(difficulty: difficulty, stability: stability, retrievability: r)
        } else {
            s = recallStability(difficulty: difficulty, stability: stability, retrievability: r, rating: g)
        }
        return clampStability(s)
    }

    private func forgetStability(difficulty: Double, stability: Double, retrievability r: Double) -> Double {
        let longTerm = parameters[11]
            * pow(difficulty, -parameters[12])
            * (pow(stability + 1, parameters[13]) - 1)
            * exp((1 - r) * parameters[14])
        let shortTerm = stability / exp(parameters[17] * parameters[18])
        return min(longTerm, shortTerm)
    }

    private func recallStability(difficulty: Double, stability: Double, retrievability r: Double, rating g: Int) -> Double {
        let hardPenalty = (g == Rating.hard.rawValue) ? parameters[15] : 1.0
        let easyBonus = (g == Rating.easy.rawValue) ? parameters[16] : 1.0
        return stability * (1
            + exp(parameters[8])
            * (11 - difficulty)
            * pow(stability, -parameters[9])
            * (exp((1 - r) * parameters[10]) - 1)
            * hardPenalty
            * easyBonus)
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

    // MARK: - Fuzz (mirrors py-fsrs _get_fuzzed_interval)

    private struct FuzzRange { let start: Double; let end: Double; let factor: Double }
    private static let fuzzRanges = [
        FuzzRange(start: 2.5, end: 7.0, factor: 0.15),
        FuzzRange(start: 7.0, end: 20.0, factor: 0.1),
        FuzzRange(start: 20.0, end: .infinity, factor: 0.05)
    ]

    private func fuzzedInterval(days: Int) -> Int {
        guard days >= 3 else { return days } // < 2.5 → no fuzz
        var delta = 1.0
        for range in FSRSScheduler.fuzzRanges {
            delta += range.factor * max(min(Double(days), range.end) - range.start, 0.0)
        }
        var minIvl = Int((Double(days) - delta).rounded())
        var maxIvl = Int((Double(days) + delta).rounded())
        minIvl = max(2, minIvl)
        maxIvl = min(maxIvl, maximumIntervalDays)
        minIvl = min(minIvl, maxIvl)
        let span = Double(maxIvl - minIvl + 1)
        var rng = SystemRandomNumberGenerator()
        let r = Double.random(in: 0..<1, using: &rng)
        let fuzzed = Int((r * span)) + minIvl
        return min(fuzzed, maximumIntervalDays)
    }
}
