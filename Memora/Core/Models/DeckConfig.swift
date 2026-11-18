//
//  DeckConfig.swift
//  Memora
//
//  Per-deck study options (section 6 of the spec). Stored as JSON in the
//  `deck_config` table so it can grow without schema migrations.
//

import Foundation

public enum NewCardOrder: String, Codable, Sendable, CaseIterable {
    case sequential     // by position / due order
    case random

    public var displayName: String {
        switch self {
        case .sequential: return "En orden"
        case .random: return "Aleatorio"
        }
    }
}

public enum ReviewCardOrder: String, Codable, Sendable, CaseIterable {
    case dueDateThenRandom
    case due
    case random

    public var displayName: String {
        switch self {
        case .dueDateThenRandom: return "Por fecha, luego aleatorio"
        case .due: return "Por fecha de vencimiento"
        case .random: return "Aleatorio"
        }
    }
}

public enum LeechAction: String, Codable, Sendable, CaseIterable {
    case suspend
    case tagOnly
}

public struct DeckConfig: Identifiable, Codable, Sendable, Hashable {
    public var id: Int64
    public var name: String

    // Daily limits
    public var newPerDay: Int
    public var reviewsPerDay: Int

    // Learning / relearning steps, in minutes.
    public var learningStepsMinutes: [Double]
    public var relearningStepsMinutes: [Double]

    // Scheduler selection
    public var scheduler: SchedulerKind

    // FSRS options
    public var desiredRetention: Double
    public var fsrsParameters: [Double]
    public var enableFuzz: Bool
    public var maximumIntervalDays: Int

    // SM-2 options
    public var startingEase: Int          // permille (2500)
    public var easyBonus: Double          // 1.3
    public var intervalModifier: Double   // 1.0
    public var hardIntervalMultiplier: Double // 1.2
    public var lapseNewIntervalPercent: Double // 0.0...1.0
    public var minimumIntervalDays: Int   // 1

    // Ordering
    public var newCardOrder: NewCardOrder
    public var reviewCardOrder: ReviewCardOrder

    // Siblings / leeches
    public var buryNewSiblings: Bool
    public var buryReviewSiblings: Bool
    public var leechThreshold: Int
    public var leechAction: LeechAction

    // UI
    public var showIntervalsOnButtons: Bool

    public init(id: Int64, name: String,
                newPerDay: Int = 20, reviewsPerDay: Int = 200,
                learningStepsMinutes: [Double] = [1, 10],
                relearningStepsMinutes: [Double] = [10],
                scheduler: SchedulerKind = .fsrs,
                desiredRetention: Double = 0.9,
                fsrsParameters: [Double] = FSRSScheduler.defaultParameters,
                enableFuzz: Bool = true,
                maximumIntervalDays: Int = 36500,
                startingEase: Int = 2500,
                easyBonus: Double = 1.3,
                intervalModifier: Double = 1.0,
                hardIntervalMultiplier: Double = 1.2,
                lapseNewIntervalPercent: Double = 0.0,
                minimumIntervalDays: Int = 1,
                newCardOrder: NewCardOrder = .sequential,
                reviewCardOrder: ReviewCardOrder = .dueDateThenRandom,
                buryNewSiblings: Bool = true,
                buryReviewSiblings: Bool = true,
                leechThreshold: Int = 8,
                leechAction: LeechAction = .suspend,
                showIntervalsOnButtons: Bool = true) {
        self.id = id
        self.name = name
        self.newPerDay = newPerDay
        self.reviewsPerDay = reviewsPerDay
        self.learningStepsMinutes = learningStepsMinutes
        self.relearningStepsMinutes = relearningStepsMinutes
        self.scheduler = scheduler
        self.desiredRetention = desiredRetention
        self.fsrsParameters = fsrsParameters
        self.enableFuzz = enableFuzz
        self.maximumIntervalDays = maximumIntervalDays
        self.startingEase = startingEase
        self.easyBonus = easyBonus
        self.intervalModifier = intervalModifier
        self.hardIntervalMultiplier = hardIntervalMultiplier
        self.lapseNewIntervalPercent = lapseNewIntervalPercent
        self.minimumIntervalDays = minimumIntervalDays
        self.newCardOrder = newCardOrder
        self.reviewCardOrder = reviewCardOrder
        self.buryNewSiblings = buryNewSiblings
        self.buryReviewSiblings = buryReviewSiblings
        self.leechThreshold = leechThreshold
        self.leechAction = leechAction
        self.showIntervalsOnButtons = showIntervalsOnButtons
    }

    public static func makeDefault(id: Int64 = 1, name: String = "Predeterminada") -> DeckConfig {
        DeckConfig(id: id, name: name)
    }

    // Tolerant decoding so configs persisted by older builds keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let def = DeckConfig.makeDefault()
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? def.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? def.name
        newPerDay = try c.decodeIfPresent(Int.self, forKey: .newPerDay) ?? def.newPerDay
        reviewsPerDay = try c.decodeIfPresent(Int.self, forKey: .reviewsPerDay) ?? def.reviewsPerDay
        learningStepsMinutes = try c.decodeIfPresent([Double].self, forKey: .learningStepsMinutes) ?? def.learningStepsMinutes
        relearningStepsMinutes = try c.decodeIfPresent([Double].self, forKey: .relearningStepsMinutes) ?? def.relearningStepsMinutes
        scheduler = try c.decodeIfPresent(SchedulerKind.self, forKey: .scheduler) ?? def.scheduler
        desiredRetention = try c.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? def.desiredRetention
        fsrsParameters = try c.decodeIfPresent([Double].self, forKey: .fsrsParameters) ?? def.fsrsParameters
        enableFuzz = try c.decodeIfPresent(Bool.self, forKey: .enableFuzz) ?? def.enableFuzz
        maximumIntervalDays = try c.decodeIfPresent(Int.self, forKey: .maximumIntervalDays) ?? def.maximumIntervalDays
        startingEase = try c.decodeIfPresent(Int.self, forKey: .startingEase) ?? def.startingEase
        easyBonus = try c.decodeIfPresent(Double.self, forKey: .easyBonus) ?? def.easyBonus
        intervalModifier = try c.decodeIfPresent(Double.self, forKey: .intervalModifier) ?? def.intervalModifier
        hardIntervalMultiplier = try c.decodeIfPresent(Double.self, forKey: .hardIntervalMultiplier) ?? def.hardIntervalMultiplier
        lapseNewIntervalPercent = try c.decodeIfPresent(Double.self, forKey: .lapseNewIntervalPercent) ?? def.lapseNewIntervalPercent
        minimumIntervalDays = try c.decodeIfPresent(Int.self, forKey: .minimumIntervalDays) ?? def.minimumIntervalDays
        newCardOrder = try c.decodeIfPresent(NewCardOrder.self, forKey: .newCardOrder) ?? def.newCardOrder
        reviewCardOrder = try c.decodeIfPresent(ReviewCardOrder.self, forKey: .reviewCardOrder) ?? def.reviewCardOrder
        buryNewSiblings = try c.decodeIfPresent(Bool.self, forKey: .buryNewSiblings) ?? def.buryNewSiblings
        buryReviewSiblings = try c.decodeIfPresent(Bool.self, forKey: .buryReviewSiblings) ?? def.buryReviewSiblings
        leechThreshold = try c.decodeIfPresent(Int.self, forKey: .leechThreshold) ?? def.leechThreshold
        leechAction = try c.decodeIfPresent(LeechAction.self, forKey: .leechAction) ?? def.leechAction
        showIntervalsOnButtons = try c.decodeIfPresent(Bool.self, forKey: .showIntervalsOnButtons) ?? def.showIntervalsOnButtons
    }
}
