//
//  SM2SchedulerTests.swift
//  MemoraTests
//
//  Verifies the SM-2 easiness-factor update and interval behaviour.
//

import XCTest
@testable import Memora

final class SM2SchedulerTests: XCTestCase {

    private func scheduler() -> SM2Scheduler {
        var config = DeckConfig.makeDefault()
        config.scheduler = .sm2
        config.learningStepsMinutes = [1, 10]
        config.relearningStepsMinutes = [10]
        return SM2Scheduler(config: config)
    }

    private func reviewCard(ivl: Int = 10, ease: Int = 2500) -> Card {
        Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0, state: .review,
             intervalDays: ivl, reps: 3, lapses: 0, easeFactor: ease, lastReview: 1_700_000_000)
    }

    func testEaseUpdateFormula() {
        let s = scheduler()
        let card = reviewCard(ease: 2500)
        // EF' = EF + (0.1 - (5-q)(0.08 + (5-q)·0.02)), floored at 1.3.
        XCTAssertEqual(s.outcome(for: card, rating: .good, elapsedDays: 10, applyFuzz: false).easeFactor, 2500) // q4: +0
        XCTAssertEqual(s.outcome(for: card, rating: .easy, elapsedDays: 10, applyFuzz: false).easeFactor, 2600) // q5: +0.1
        XCTAssertEqual(s.outcome(for: card, rating: .hard, elapsedDays: 10, applyFuzz: false).easeFactor, 2360) // q3: -0.14
        XCTAssertEqual(s.outcome(for: card, rating: .again, elapsedDays: 10, applyFuzz: false).easeFactor, 1960) // q1: -0.54
    }

    func testEaseFloor() {
        let s = scheduler()
        let card = reviewCard(ease: 1400)
        // Again from a low ease must not drop below 1300.
        XCTAssertEqual(s.outcome(for: card, rating: .again, elapsedDays: 10, applyFuzz: false).easeFactor, 1300)
    }

    func testIntervalGrowthOrdering() {
        let s = scheduler()
        let card = reviewCard(ivl: 10, ease: 2500)
        func ivl(_ r: Rating) -> Int {
            if case .days(let d) = s.outcome(for: card, rating: r, elapsedDays: 10, applyFuzz: false).interval { return d }
            return 0
        }
        XCTAssertGreaterThan(ivl(.easy), ivl(.good))
        XCTAssertGreaterThan(ivl(.good), ivl(.hard))
        XCTAssertGreaterThanOrEqual(ivl(.hard), 11) // always grows by at least 1
    }

    func testAgainEntersRelearningAndLapses() {
        let s = scheduler()
        let card = reviewCard(ivl: 20)
        let outcome = s.outcome(for: card, rating: .again, elapsedDays: 20, applyFuzz: false)
        XCTAssertEqual(outcome.state, .relearning)
        XCTAssertEqual(outcome.lapses, 1)
        if case .seconds(let sec) = outcome.interval {
            XCTAssertEqual(sec, 600) // first relearning step, 10 min
        } else {
            XCTFail("expected a sub-day relearning step")
        }
    }

    func testNewCardLearningProgression() {
        let s = scheduler()
        let newCard = Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0, state: .new)
        // Good on step 0 -> learning step 1 (10 min).
        let step1 = s.outcome(for: newCard, rating: .good, elapsedDays: 0, applyFuzz: false)
        XCTAssertEqual(step1.state, .learning)
        if case .seconds(let sec) = step1.interval { XCTAssertEqual(sec, 600) } else { XCTFail() }
        // Good again on last step -> graduate to review.
        var card = newCard; card.state = .learning; card.learningStep = 1
        let grad = s.outcome(for: card, rating: .good, elapsedDays: 0, applyFuzz: false)
        XCTAssertEqual(grad.state, .review)
        if case .days(let d) = grad.interval { XCTAssertEqual(d, 1) } else { XCTFail() }
    }
}
