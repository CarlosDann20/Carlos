//
//  CollectionSettings.swift
//  Memora
//
//  Collection-wide settings that affect scheduling (day rollover) and that we
//  preserve from an imported Anki collection where possible.
//

import Foundation

public struct CollectionSettings: Sendable, Hashable {
    /// Collection creation time, epoch seconds. Used as the anchor for the
    /// "study day" calculation.
    public var creationEpoch: Int64
    /// The hour (0...23, local time) at which a new study day begins. Anki's
    /// default is 4 AM so late-night study still counts as "yesterday".
    public var rolloverHour: Int
    /// App schema/version marker for migrations.
    public var schemaVersion: Int

    public init(creationEpoch: Int64, rolloverHour: Int = 4, schemaVersion: Int = 1) {
        self.creationEpoch = creationEpoch
        self.rolloverHour = rolloverHour
        self.schemaVersion = schemaVersion
    }

    public static func makeDefault() -> CollectionSettings {
        CollectionSettings(creationEpoch: Int64(Date().timeIntervalSince1970))
    }
}
