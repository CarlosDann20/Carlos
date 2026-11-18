//
//  Rating.swift
//  Memora
//
//  The four review grades, numbered to match both Anki (`ease` 1...4) and the
//  FSRS reference implementation (`Rating` 1...4). Keeping the raw values in
//  sync is what lets imported Anki review history line up with Memora's
//  schedulers.
//

import Foundation

public enum Rating: Int, CaseIterable, Codable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var localizedTitle: String {
        switch self {
        case .again: return "Otra vez"
        case .hard: return "Difícil"
        case .good: return "Bien"
        case .easy: return "Fácil"
        }
    }

    public var englishTitle: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}
