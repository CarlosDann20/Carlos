//
//  Note.swift
//  Memora
//
//  A note is the unit of content a user enters; one note generates one or more
//  cards via its note type's templates (or via cloze deletions).
//

import Foundation

/// The field separator Anki uses to join note fields in storage (unit
/// separator, 0x1F).
public let ankiFieldSeparator: Character = "\u{1f}"

public struct Note: Identifiable, Sendable, Hashable {
    public var id: Int64
    /// Globally unique id used for cross-collection dedup (Anki `guid`).
    public var guid: String
    public var notetypeID: Int64
    public var modified: Int64
    /// Ordered field values.
    public var fields: [String]
    /// Normalized tags (no surrounding spaces, no duplicates).
    public var tags: [String]
    /// Checksum of the first field's stripped text, for duplicate detection
    /// (matches Anki's `csum`).
    public var checksum: Int64

    public init(id: Int64, guid: String, notetypeID: Int64, modified: Int64,
                fields: [String], tags: [String], checksum: Int64) {
        self.id = id
        self.guid = guid
        self.notetypeID = notetypeID
        self.modified = modified
        self.fields = fields
        self.tags = tags
        self.checksum = checksum
    }

    /// Joined storage representation of the fields.
    public var joinedFields: String {
        fields.joined(separator: String(ankiFieldSeparator))
    }

    public static func splitFields(_ joined: String) -> [String] {
        joined.components(separatedBy: String(ankiFieldSeparator))
    }

    public var tagString: String {
        tags.isEmpty ? "" : " " + tags.joined(separator: " ") + " "
    }
}
