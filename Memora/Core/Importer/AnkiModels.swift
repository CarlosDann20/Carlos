//
//  AnkiModels.swift
//  Memora
//
//  Decodable representations of the JSON stored in the `col` table of a
//  schema-11 Anki collection (models and decks), plus the row structs for
//  notes / cards / revlog. Field names and semantics follow the Anki source
//  (rslib schema11.sql and the collection JSON). Decoding is tolerant:
//  unknown keys are ignored and missing keys fall back to sensible defaults,
//  so quirks across Anki versions don't abort an import.
//

import Foundation

// MARK: - Models (note types)

struct AnkiModelField: Decodable {
    var name: String
    var ord: Int
    var rtl: Bool?
    var font: String?
    var size: Int?
    var sticky: Bool?
    var description: String?

    private enum CodingKeys: String, CodingKey { case name, ord, rtl, font, size, sticky, description }
}

struct AnkiModelTemplate: Decodable {
    var name: String
    var ord: Int
    var qfmt: String
    var afmt: String
    var did: Int64?

    private enum CodingKeys: String, CodingKey { case name, ord, qfmt, afmt, did }
}

struct AnkiModel: Decodable {
    var id: Int64
    var name: String
    var type: Int          // 0 standard, 1 cloze
    var css: String?
    var flds: [AnkiModelField]
    var tmpls: [AnkiModelTemplate]
    var sortf: Int?        // sort field index
    var latexPre: String?
    var latexPost: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, css, flds, tmpls, sortf, latexPre, latexPost
    }
}

// MARK: - Decks

struct AnkiDeck: Decodable {
    var id: Int64
    var name: String
    var dyn: Int?          // 1 = filtered deck
    var conf: Int64?       // deck options group id
    var collapsed: Bool?

    private enum CodingKeys: String, CodingKey { case id, name, dyn, conf, collapsed }
}

// MARK: - Deck options (dconf)

struct AnkiDeckConfig: Decodable {
    struct NewConf: Decodable { var perDay: Int?; var delays: [Double]?; var initialFactor: Int? }
    struct RevConf: Decodable { var perDay: Int?; var ivlFct: Double?; var maxIvl: Int?; var hardFactor: Double? }
    struct LapseConf: Decodable { var delays: [Double]?; var mult: Double?; var leechFails: Int?; var leechAction: Int? }

    var id: Int64
    var name: String
    var new: NewConf?
    var rev: RevConf?
    var lapse: LapseConf?

    private enum CodingKeys: String, CodingKey { case id, name, new, rev, lapse }
}

// MARK: - Row structs

struct AnkiNoteRow {
    var id: Int64
    var guid: String
    var mid: Int64
    var mod: Int64
    var tags: String
    var flds: String
}

struct AnkiCardRow {
    var id: Int64
    var nid: Int64
    var did: Int64
    var ord: Int
    var type: Int
    var queue: Int
    var due: Int64
    var ivl: Int
    var factor: Int
    var reps: Int
    var lapses: Int
    var left: Int
    var odue: Int64
    var odid: Int64
    var data: String
}

struct AnkiRevlogRow {
    var id: Int64
    var cid: Int64
    var ease: Int
    var ivl: Int
    var lastIvl: Int
    var factor: Int
    var time: Int
    var type: Int
}

/// FSRS memory state that modern Anki stores in `cards.data`.
struct AnkiCardData: Decodable {
    var s: Double?   // stability
    var d: Double?   // difficulty
    var pos: Int64?  // original new-card position
}
