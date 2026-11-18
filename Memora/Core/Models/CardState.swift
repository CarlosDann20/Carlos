//
//  CardState.swift
//  Memora
//
//  Memora's internal scheduling state plus helpers to translate to/from the
//  Anki `cards.type` / `cards.queue` representation used in .apkg files.
//

import Foundation

/// The learning state of a card. Raw values are Memora's own and are stored in
/// the database; Anki translation happens in the importer/exporter only.
public enum CardState: Int, Codable, Sendable, CaseIterable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

/// How a card is buried, mirroring Anki's negative queue values.
public enum BuryState: Int, Codable, Sendable {
    case none = 0
    case manual = 1   // Anki queue -3
    case sibling = 2  // Anki queue -2
}

public enum SchedulerKind: String, Codable, Sendable, CaseIterable {
    case fsrs
    case sm2

    public var displayName: String {
        switch self {
        case .fsrs: return "FSRS (recomendado)"
        case .sm2: return "SM-2 (clásico)"
        }
    }
}

// MARK: - Anki card.type / card.queue mapping

public enum AnkiCardType: Int {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

public enum AnkiCardQueue: Int {
    case manuallyBuried = -3
    case siblingBuried = -2
    case suspended = -1
    case new = 0
    case learning = 1    // intra-day learning (due is a timestamp)
    case review = 2      // due is a day number
    case dayLearning = 3 // inter-day learning (due is a day number)
    case preview = 4
}

extension CardState {
    /// Best-effort mapping from an Anki `type` value.
    public static func fromAnki(type: Int) -> CardState {
        switch AnkiCardType(rawValue: type) {
        case .new: return .new
        case .learning: return .learning
        case .review: return .review
        case .relearning: return .relearning
        case .none: return .new
        }
    }

    /// Anki `type` value for export.
    public var ankiType: Int {
        switch self {
        case .new: return 0
        case .learning: return 1
        case .review: return 2
        case .relearning: return 3
        }
    }
}
