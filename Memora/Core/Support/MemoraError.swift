//
//  MemoraError.swift
//  Memora
//
//  Central, user-presentable error type. Every error surfaced to the UI
//  carries a localized, human-readable message (Spanish-first, matching the
//  product's primary audience) plus optional recovery guidance.
//

import Foundation

public struct MemoraError: LocalizedError {
    public enum Kind: Equatable {
        case importFailed
        case unsupportedPackage
        case corruptPackage
        case ioFailure
        case databaseFailure
        case exportFailed
        case notFound
        case invalidState
        case security
    }

    public let kind: Kind
    public let message: String
    public let recovery: String?
    public let underlying: String?

    public init(_ kind: Kind, _ message: String, recovery: String? = nil, underlying: Error? = nil) {
        self.kind = kind
        self.message = message
        self.recovery = recovery
        self.underlying = underlying.map { String(describing: $0) }
    }

    public var errorDescription: String? { message }
    public var recoverySuggestion: String? { recovery }

    // MARK: - Common constructors

    public static func unsupported(_ message: String, recovery: String? = nil) -> MemoraError {
        MemoraError(.unsupportedPackage, message, recovery: recovery)
    }

    public static func corrupt(_ message: String, underlying: Error? = nil) -> MemoraError {
        MemoraError(.corruptPackage, message, underlying: underlying)
    }

    public static func security(_ message: String) -> MemoraError {
        MemoraError(.security, message)
    }

    public static func db(_ message: String, underlying: Error? = nil) -> MemoraError {
        MemoraError(.databaseFailure, message, underlying: underlying)
    }
}
