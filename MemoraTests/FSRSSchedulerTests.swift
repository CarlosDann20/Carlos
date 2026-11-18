//
//  FSRSSchedulerTests.swift
//  MemoraTests
//
//  Golden-value tests for the FSRS-6 port. Expected numbers were produced by
//  the reference implementation py-fsrs (fuzz disabled) and are reproduced in
//  scripts/validate_fsrs.py, which this suite mirrors.
//

import XCTest
@testable import Memora

final class FSRSSchedulerTests: XCTestCase {

    private func scheduler(fuzz: Bool = false) -> FSRSScheduler {
        FSRSScheduler(parameters: FSRSScheduler.defaultParameters, desiredRetention: 0.9,
                      learningStepsMinutes: [1, 10], relearningStepsMinutes: [10],
                      maximumIntervalDays: 36500, enableFuzz: fuzz)
    }

    func testDefaultParametersAreFSRS6() {
        XCTAssertEqual(FSRSScheduler.defaultParameters.count, 21)
        XCTAssertEqual(FSRSScheduler.defaultParameters[0], 0.212, accuracy: 1e-9)
        XCTAssertEqual(FSRSScheduler.defaultParameters[20], 0.1542, accuracy: 1e-9)
    }

    func testInitialStabilityAndDifficulty() {
        let s = scheduler()
        // First review of a new card with each rating sets S0 = w[g-1].
        let expectedS: [Rating: Double] = [.again: 0.212, .hard: 1.2931, .good: 2.3065, .easy: 8.2956]
        for (rating, sExp) in expectedS {
            let card = Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0, state: .new)
            let outcome = s.outcome(for: card, rating: rating, elapsedDays: 0, applyFuzz: false)
            XCTAssertEqual(outcome.stability ?? -1, sExp, accuracy: 1e-6, "S0 for \(rating)")
        }
        // Initial difficulty for Good.
        let card = Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0, state: .new)
        let good = s.outcome(for: card, rating: .good, elapsedDays: 0, applyFuzz: false)
        XCTAssertEqual(good.difficulty ?? -1, 2.1181039705, accuracy: 1e-6)
    }

    func testGoldenSequence() {
        let s = scheduler()
        // (rating, gapDays) -> expected (state, S, D, intervalDays) from py-fsrs.
        struct Step { let g: Rating; let gap: Int; let state: CardState; let S: Double; let D: Double; let ivl: Double }
        let steps: [Step] = [
            Step(g: .good, gap: 0, state: .learning, S: 2.3065000000, D: 2.1181039705, ivl: 600.0 / 86400),
            Step(g: .good, gap: 0, state: .review, S: 2.3065000000, D: 2.1112142358, ivl: 2),
            Step(g: .good, gap: 1, state: .review, S: 7.3191860978, D: 2.1043313908, ivl: 7),
            Step(g: .easy, gap: 4, state: .review, S: 37.0723975880, D: 1.0000000000, ivl: 37),
            Step(g: .good, gap: 10, state: .review, S: 74.9548410371, D: 1.0000000000, ivl: 75),
            Step(g: .again, gap: 20, state: .relearning, S: 3.3356242563, D: 7.0269895693, ivl: 600.0 / 86400),
            Step(g: .good, gap: 0, state: .review, S: 3.3356242563, D: 7.0151909490, ivl: 3),
            Step(g: .good, gap: 2, state: .review, S: 7.3170492718, D: 7.0034041274, ivl: 7),
            Step(g: .hard, gap: 6, state: .review, S: 13.2000381787, D: 7.9959483877, ivl: 13),
            Step(g: .good, gap: 15, state: .review, S: 28.4083277253, D: 7.9831808086, ivl: 28),
        ]
        var card = Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0, state: .new)
        var lastReview: Int64? = nil
        var now: Int64 = 1_700_000_000
        for (i, step) in steps.enumerated() {
            now += Int64(step.gap) * 86_400
            let elapsed = lastReview == nil ? 0 : max(0, Int((now - lastReview!) / 86_400))
            let outcome = s.outcome(for: card, rating: step.g, elapsedDays: elapsed, applyFuzz: false)
            XCTAssertEqual(outcome.state, step.state, "state at step \(i)")
            XCTAssertEqual(outcome.stability ?? -1, step.S, accuracy: 1e-5, "S at step \(i)")
            XCTAssertEqual(outcome.difficulty ?? -1, step.D, accuracy: 1e-5, "D at step \(i)")
            switch outcome.interval {
            case .days(let d): XCTAssertEqual(Double(d), step.ivl, accuracy: 0.5, "ivl days at step \(i)")
            case .seconds(let sec): XCTAssertEqual(Double(sec) / 86_400, step.ivl, accuracy: 0.001, "ivl secs at step \(i)")
            }
            card.state = outcome.state
            card.learningStep = outcome.learningStep
            card.stability = outcome.stability
            card.difficulty = outcome.difficulty
            card.lastReview = now
            lastReview = now
        }
    }

    func testRetrievabilityDecreasesOverTime() {
        let s = scheduler()
        let r0 = s.retrievability(elapsedDays: 0, stability: 10)
        let r10 = s.retrievability(elapsedDays: 10, stability: 10)
        let r100 = s.retrievability(elapsedDays: 100, stability: 10)
        XCTAssertEqual(r0, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(r10, r0)
        XCTAssertLessThan(r100, r10)
        // At t == S, retrievability should be the target 0.9.
        XCTAssertEqual(s.retrievability(elapsedDays: 10, stability: 10), 0.9, accuracy: 1e-6)
    }

    func testEasyGivesLongerIntervalThanGoodThanHard() {
        let s = scheduler()
        let card = Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0, state: .review,
                        intervalDays: 10, stability: 10, difficulty: 5, lastReview: 1_700_000_000)
        func ivl(_ r: Rating) -> Int {
            if case .days(let d) = s.outcome(for: card, rating: r, elapsedDays: 10, applyFuzz: false).interval { return d }
            return 0
        }
        XCTAssertGreaterThan(ivl(.easy), ivl(.good))
        XCTAssertGreaterThan(ivl(.good), ivl(.hard))
    }
}
