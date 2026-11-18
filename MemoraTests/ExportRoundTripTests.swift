//
//  ExportRoundTripTests.swift
//  MemoraTests
//
//  Imports a fixture, exports it to a legacy .apkg, then re-imports into a
//  fresh store and verifies the content survived the round trip.
//

import XCTest
@testable import Memora

final class ExportRoundTripTests: XCTestCase {

    func testExportThenReimport() throws {
        let (store1, dir1) = try TestSupport.makeFileStore()
        defer { TestSupport.cleanup(dir1) }
        let fixture = try XCTUnwrap(TestSupport.fixtureURL("basic"))
        _ = try AnkiImporter(store: store1).importPackage(at: fixture)
        let originalNotes = try store1.noteCount()
        XCTAssertEqual(originalNotes, 3)

        // Export the whole collection with scheduling.
        let exportURL = dir1.appendingPathComponent("export.apkg")
        try AnkiExporter(store: store1).export(deckIDs: nil, includeScheduling: true, to: exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        // Re-import into a fresh store.
        let (store2, dir2) = try TestSupport.makeFileStore()
        defer { TestSupport.cleanup(dir2) }
        let summary = try AnkiImporter(store: store2).importPackage(at: exportURL)

        XCTAssertEqual(summary.notesImported, 3, "all notes should round-trip")
        XCTAssertEqual(try store2.cardCount(), try store1.cardCount())
        XCTAssertTrue(try store2.allTags().contains("geografía"), "tags survive the round trip")

        // Cloze still searchable.
        var filter = CardBrowseFilter(); filter.text = "madrid"
        XCTAssertFalse(try store2.browse(filter).isEmpty)

        // Media survives.
        XCTAssertTrue(FileManager.default.fileExists(atPath: store2.mediaFileURL("img.png").path))

        // Note types survive (basic + cloze).
        XCTAssertEqual(try store2.allNotetypes().count, 2)
    }

    func testExportProducesValidZip() throws {
        let (store, dir) = try TestSupport.makeFileStore()
        defer { TestSupport.cleanup(dir) }
        let fixture = try XCTUnwrap(TestSupport.fixtureURL("legacy1"))
        _ = try AnkiImporter(store: store).importPackage(at: fixture)
        let url = dir.appendingPathComponent("out.apkg")
        try AnkiExporter(store: store).export(deckIDs: nil, includeScheduling: false, to: url)

        // The exported archive must be a readable ZIP containing a collection.
        let zip = try ZipReader(url: url)
        XCTAssertTrue(zip.contains("collection.anki2"))
        XCTAssertTrue(zip.contains("media"))
    }
}
