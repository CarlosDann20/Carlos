//
//  SHA1.swift
//  Memora
//
//  SHA-1 is used only for Anki-compatible field checksums and media
//  deduplication (matching Anki's media manager). It is not used for any
//  security purpose. Backed by CryptoKit's Insecure.SHA1 on Apple platforms.
//

import Foundation
import CryptoKit

public enum SHA1 {
    public static func hash(_ data: Data) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: data))
    }

    public static func hexString(_ data: Data) -> String {
        hash(data).map { String(format: "%02x", $0) }.joined()
    }
}
