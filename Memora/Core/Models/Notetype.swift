//
//  Notetype.swift
//  Memora
//
//  A "note type" (Anki calls it a model): the set of fields, the card
//  templates, and the shared CSS. Imported faithfully from Anki so that cards
//  render with their original layout.
//

import Foundation

public enum NotetypeKind: Int, Codable, Sendable {
    case standard = 0
    case cloze = 1
}

public struct NoteField: Codable, Sendable, Identifiable, Hashable {
    public var id: Int { ord }
    public var ord: Int
    public var name: String
    public var rightToLeft: Bool
    public var fontFamily: String
    public var fontSize: Int
    public var sticky: Bool
    public var descriptionText: String

    public init(ord: Int, name: String, rightToLeft: Bool = false,
                fontFamily: String = "Arial", fontSize: Int = 20,
                sticky: Bool = false, descriptionText: String = "") {
        self.ord = ord
        self.name = name
        self.rightToLeft = rightToLeft
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.sticky = sticky
        self.descriptionText = descriptionText
    }
}

public struct CardTemplate: Codable, Sendable, Identifiable, Hashable {
    public var id: Int { ord }
    public var ord: Int
    public var name: String
    /// Question format (front), Anki mustache-like template.
    public var questionFormat: String
    /// Answer format (back).
    public var answerFormat: String
    /// Optional deck override id for this template (Anki `did`).
    public var deckOverrideID: Int64?

    public init(ord: Int, name: String, questionFormat: String, answerFormat: String, deckOverrideID: Int64? = nil) {
        self.ord = ord
        self.name = name
        self.questionFormat = questionFormat
        self.answerFormat = answerFormat
        self.deckOverrideID = deckOverrideID
    }
}

public struct Notetype: Codable, Sendable, Identifiable, Hashable {
    public var id: Int64
    public var name: String
    public var kind: NotetypeKind
    public var css: String
    public var fields: [NoteField]
    public var templates: [CardTemplate]
    public var latexPre: String
    public var latexPost: String
    /// Index of the field used for sorting / dedup display.
    public var sortFieldIndex: Int
    public var modified: Int64

    public init(id: Int64, name: String, kind: NotetypeKind, css: String,
                fields: [NoteField], templates: [CardTemplate],
                latexPre: String = "", latexPost: String = "",
                sortFieldIndex: Int = 0, modified: Int64 = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.css = css
        self.fields = fields
        self.templates = templates
        self.latexPre = latexPre
        self.latexPost = latexPost
        self.sortFieldIndex = sortFieldIndex
        self.modified = modified
    }

    public func field(named name: String) -> NoteField? {
        fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
