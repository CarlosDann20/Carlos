//
//  MediaItem.swift
//  Memora
//
//  Metadata for a media file (image / audio). The bytes live on disk in the
//  collection's media directory; this record tracks name, size and checksum
//  for dedup and backup.
//

import Foundation

public struct MediaItem: Sendable, Hashable {
    public var filename: String
    public var size: Int
    public var sha1Hex: String

    public init(filename: String, size: Int, sha1Hex: String) {
        self.filename = filename
        self.size = size
        self.sha1Hex = sha1Hex
    }
}
