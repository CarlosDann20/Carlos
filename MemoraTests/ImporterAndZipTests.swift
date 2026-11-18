//
//  ImporterAndZipTests.swift
//  MemoraTests
//
//  Exercises the ZIP reader and the Anki importer against real .apkg fixtures
//  (built by scripts/make_apkg.py). Covers spec section 12 items: basic import,
//  large import (4000+), cloze, media, tags, scheduling preservation, FSRS
//  carry-over, dedup, and v3 detection.
//

import XCTest
@testable import Memora

final class ImporterAndZipTests: XCTestCase {

    private var store: MemoraStore!
    private var dir: URL!

    override func setUpWithError() throws {
        (store, dir) = try TestSupport.makeFileStore()
    }
    override func tearDownWithError() throws {
        TestSupport.cleanup(dir)
    }

    private func importFixture(_ name: String) throws -> ImportSummary {
        let url = try XCTUnwrap(TestSupport.fixtureURL(name), "missing fixture \(name).apkg")
        return try AnkiImporter(store: store).importPackage(at: url)
    }

    func testZipReaderReadsApkg() throws {
        let url = try XCTUnwrap(TestSupport.fixtureURL("basic"))
        let zip = try ZipReader(url: url)
        XCTAssertTrue(zip.contains("collection.anki21"))
        XCTAssertTrue(zip.contains("media"))
        XCTAssertTrue(zip.contains("0"))
        let mediaJSON = try zip.data(forName: "media")
        let map = try JSONSerialization.jsonObject(with: mediaJSON) as? [String: String]
        XCTAssertEqual(map?["0"], "img.png")
    }

    func testImportBasic() throws {
        let summary = try importFixture("basic")
        XCTAssertEqual(summary.notesImported, 3)
        XCTAssertEqual(summary.cardsImported, 3)
        XCTAssertEqual(try store.noteCount(), 3)

        // Decks: subdeck created.
        let decks = try store.allDecks().map { $0.name }
        XCTAssertTrue(decks.contains("Español::Verbos"))
        XCTAssertTrue(decks.contains("Español"))

        // Note types: basic + cloze.
        XCTAssertEqual(try store.allNotetypes().count, 2)
        XCTAssertTrue(try store.allNotetypes().contains { $0.kind == .cloze })

        // Tags preserved.
        XCTAssertTrue(try store.allTags().contains("geografía"))
        XCTAssertTrue(try store.allTags().contains("idiomas"))
    }

    func testImportMediaWritten() throws {
        _ = try importFixture("basic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaFileURL("img.png").path),
                      "media file should be written to disk")
        XCTAssertEqual(try store.mediaCount(), 1)
    }

    func testImportClozePreserved() throws {
        _ = try importFixture("basic")
        var filter = CardBrowseFilter()
        filter.text = "madrid"
        let rows = try store.browse(filter)
        XCTAssertFalse(rows.isEmpty, "cloze note should be searchable")
    }

    func testSchedulingAndFSRSPreserved() throws {
        _ = try importFixture("basic")
        // The "Perro/Dog" note was imported as a review card with FSRS memory.
        let cards = try store.db.query("SELECT \(MemoraStore.cardColumns) FROM cards WHERE state = 2") { MemoraStore.card(from: $0) }
        XCTAssertFalse(cards.isEmpty)
        let fsrsCard = cards.first { $0.stability != nil }
        XCTAssertNotNil(fsrsCard, "FSRS stability should be carried over from cards.data")
        XCTAssertEqual(fsrsCard?.stability ?? 0, 12.34, accuracy: 1e-6)
        XCTAssertEqual(fsrsCard?.difficulty ?? 0, 5.67, accuracy: 1e-6)
        XCTAssertEqual(fsrsCard?.intervalDays, 12)
        XCTAssertEqual(fsrsCard?.easeFactor, 2600)
        XCTAssertEqual(fsrsCard?.reps, 4)
        XCTAssertEqual(fsrsCard?.lapses, 1)
    }

    func testReviewLogImported() throws {
        _ = try importFixture("basic")
        let revCount = try store.db.scalarInt("SELECT COUNT(*) FROM revlog")
        XCTAssertEqual(revCount, 2)
    }

    func testImportLegacy1() throws {
        let summary = try importFixture("legacy1")
        XCTAssertEqual(summary.notesImported, 1)
        XCTAssertEqual(summary.cardsImported, 1)
        XCTAssertEqual(summary.sourceVersion, "Legacy (schema 11)")
    }

    func testImportLargeCollection() throws {
        let summary = try importFixture("large")
        XCTAssertEqual(summary.notesImported, 4000)
        XCTAssertEqual(summary.cardsImported, 4000)
        XCTAssertEqual(try store.cardCount(), 4000)
    }

    func testDedupOnReimport() throws {
        let first = try importFixture("basic")
        XCTAssertEqual(first.notesImported, 3)
        let second = try importFixture("basic")
        XCTAssertEqual(second.notesImported, 0, "re-import must not duplicate notes")
        XCTAssertEqual(second.notesDuplicate, 3)
        XCTAssertEqual(try store.noteCount(), 3, "total notes unchanged after re-import")
    }

    func testV3PackageRejectedWithGuidance() throws {
        let url = try XCTUnwrap(TestSupport.fixtureURL("v3stub"))
        XCTAssertThrowsError(try AnkiImporter(store: store).importPackage(at: url)) { error in
            guard let m = error as? MemoraError else { return XCTFail("expected MemoraError") }
            XCTAssertEqual(m.kind, .unsupportedPackage)
            XCTAssertNotNil(m.recovery, "should include guidance to re-export")
        }
    }

    func testImportIsNonDestructiveOnFailure() throws {
        // Seed a note, then attempt a failing import; the seed must survive.
        _ = try store.addNote(notetypeID: seedNotetype(), deckID: 1, fields: ["A", "B"], tags: [])
        let before = try store.noteCount()
        let url = try XCTUnwrap(TestSupport.fixtureURL("v3stub"))
        XCTAssertThrowsError(try AnkiImporter(store: store).importPackage(at: url))
        XCTAssertEqual(try store.noteCount(), before, "failed import must not alter existing data")
    }

    private func seedNotetype() throws -> Int64 {
        let nt = Notetype(id: 999, name: "Prueba", kind: .standard, css: "",
                          fields: [NoteField(ord: 0, name: "Frente"), NoteField(ord: 1, name: "Reverso")],
                          templates: [CardTemplate(ord: 0, name: "Tarjeta", questionFormat: "{{Frente}}", answerFormat: "{{Reverso}}")])
        try store.upsertNotetype(nt)
        return 999
    }
}
