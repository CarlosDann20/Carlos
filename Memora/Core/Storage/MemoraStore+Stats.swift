//
//  MemoraStore+Stats.swift
//  Memora
//
//  Statistics queries over `revlog` and `cards`. Day bucketing honours the
//  collection's rollover hour via DayClock. All computation is local.
//

import Foundation

public struct TodayStats: Sendable, Hashable {
    public var answered: Int = 0
    public var uniqueCards: Int = 0
    public var newIntroduced: Int = 0
    public var reviewsDone: Int = 0
    public var learningDone: Int = 0
    public var correct: Int = 0
    public var timeMS: Int = 0
    public var retentionPercent: Double { answered == 0 ? 0 : Double(correct) / Double(answered) * 100 }
    public var timeMinutes: Double { Double(timeMS) / 60000.0 }
}

public struct DayBucket: Sendable, Hashable, Identifiable {
    public var id: Int { dayNumber }
    public var dayNumber: Int
    public var startEpoch: Int64
    public var reviews: Int
    public var timeMS: Int
    public var correct: Int
    public var newCards: Int
}

public struct StateDistribution: Sendable, Hashable {
    public var new = 0
    public var learning = 0
    public var youngReview = 0   // review, interval < 21 days
    public var matureReview = 0  // review, interval >= 21 days
    public var relearning = 0
    public var suspended = 0
    public var total: Int { new + learning + youngReview + matureReview + relearning + suspended }
}

public struct DueForecastBucket: Sendable, Hashable, Identifiable {
    public var id: Int { dayOffset }
    public var dayOffset: Int
    public var count: Int
}

extension MemoraStore {

    public func todayStats(now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> TodayStats {
        let clock = try dayClock()
        let start = clock.startEpoch(ofDay: clock.today(now: now))
        var stats = TodayStats()
        try db.query("""
            SELECT rating, state_before, time_ms, card_id FROM revlog
            WHERE reviewed_at >= ? AND reviewed_at <= ?
            """, [.integer(start), .integer(now)]) { row -> Void in
            stats.answered += 1
            if row.int(0) != Int64(Rating.again.rawValue) { stats.correct += 1 }
            let stateBefore = Int(row.int(1))
            if stateBefore == CardState.new.rawValue { stats.newIntroduced += 1 }
            else if stateBefore == CardState.review.rawValue { stats.reviewsDone += 1 }
            else { stats.learningDone += 1 }
            stats.timeMS += Int(row.int(2))
        }
        stats.uniqueCards = Int(try db.scalarInt(
            "SELECT COUNT(DISTINCT card_id) FROM revlog WHERE reviewed_at >= ? AND reviewed_at <= ?",
            [.integer(start), .integer(now)]))
        return stats
    }

    /// Per-day review counts for the last `daysBack` days (for the history
    /// chart and the activity calendar).
    public func dailyBuckets(daysBack: Int, now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> [DayBucket] {
        let clock = try dayClock()
        let today = clock.today(now: now)
        let firstDay = today - daysBack + 1
        let windowStart = clock.startEpoch(ofDay: firstDay)
        var buckets: [Int: DayBucket] = [:]
        for d in firstDay...today {
            buckets[d] = DayBucket(dayNumber: d, startEpoch: clock.startEpoch(ofDay: d),
                                   reviews: 0, timeMS: 0, correct: 0, newCards: 0)
        }
        try db.query("""
            SELECT reviewed_at, time_ms, rating, state_before FROM revlog WHERE reviewed_at >= ?
            """, [.integer(windowStart)]) { row -> Void in
            let day = clock.dayNumber(for: row.int(0))
            guard var bucket = buckets[day] else { return }
            bucket.reviews += 1
            bucket.timeMS += Int(row.int(1))
            if row.int(2) != Int64(Rating.again.rawValue) { bucket.correct += 1 }
            if Int(row.int(3)) == CardState.new.rawValue { bucket.newCards += 1 }
            buckets[day] = bucket
        }
        return buckets.values.sorted { $0.dayNumber < $1.dayNumber }
    }

    public func stateDistribution(deckIDs: [Int64]? = nil) throws -> StateDistribution {
        var dist = StateDistribution()
        var sql = "SELECT state, suspended, ivl, COUNT(*) FROM cards"
        var values: [SQLiteValue] = []
        if let deckIDs, !deckIDs.isEmpty {
            sql += " WHERE deck_id IN (\(deckIDs.map { _ in "?" }.joined(separator: ",")))"
            values = deckIDs.map { .integer($0) }
        }
        sql += " GROUP BY state, suspended, (ivl >= 21)"
        try db.query(sql, values) { row -> Void in
            let state = Int(row.int(0))
            let suspended = row.int(1) != 0
            let ivl = Int(row.int(2))
            let count = Int(row.int(3))
            if suspended { dist.suspended += count; return }
            switch CardState(rawValue: state) ?? .new {
            case .new: dist.new += count
            case .learning: dist.learning += count
            case .relearning: dist.relearning += count
            case .review: if ivl >= 21 { dist.matureReview += count } else { dist.youngReview += count }
            }
        }
        return dist
    }

    /// Upcoming due counts (review + learning) for the next `days` days.
    public func dueForecast(days: Int, now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> [DueForecastBucket] {
        let clock = try dayClock()
        let today = clock.today(now: now)
        let end = clock.startEpoch(ofDay: today + days + 1)
        var buckets = [Int: Int]()
        for d in 0...days { buckets[d] = 0 }
        try db.query("""
            SELECT due FROM cards WHERE state IN (1,2,3) AND suspended = 0 AND bury = 0 AND due < ?
            """, [.integer(end)]) { row -> Void in
            let offset = max(0, clock.dayNumber(for: row.int(0)) - today)
            if offset <= days { buckets[offset, default: 0] += 1 }
        }
        return buckets.map { DueForecastBucket(dayOffset: $0.key, count: $0.value) }.sorted { $0.dayOffset < $1.dayOffset }
    }

    public func totalStudyTimeMS() throws -> Int64 { try db.scalarInt("SELECT COALESCE(SUM(time_ms),0) FROM revlog") }

    public func totalReviews() throws -> Int { Int(try db.scalarInt("SELECT COUNT(*) FROM revlog")) }
}
