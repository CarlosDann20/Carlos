//
//  MemoraTestSupport.swift
//  MemoraTests
//

import XCTest
@testable import Memora

final class TestBundleMarker {}

enum TestSupport {
    /// A file-backed store in a fresh temp directory (needed for backup /
    /// restore / persistence tests).
    static func makeFileStore() throws -> (store: MemoraStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("memora-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try MemoraStore(databaseURL: dir.appendingPathComponent("collection.sqlite"),
                                    mediaDirectory: dir.appendingPathComponent("media"))
        return (store, dir)
    }

    static func fixtureURL(_ name: String, ext: String = "apkg") -> URL? {
        let bundle = Bundle(for: TestBundleMarker.self)
        if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        // Fallback: Fixtures subdirectory, in case the resource is foldered.
        return bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
    }

    static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
