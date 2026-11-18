//
//  StoreTests.swift
//  MemoraTests
//
//  Store CRUD, card generation, search, deck counts, persistence across
//  reopen, and backup/restore.
//

import XCTest
@testable import Memora

final class StoreTests: XCTestCase {

    private var store: MemoraStore!
    private var dir: URL!

    override func setUpWithError() throws { (store, dir) = try TestSupport.makeFileStore() }
    override func tearDownWithError() throws { TestSupport.cleanup(dir) }

    private func basicNotetype() throws -> Int64 {
        let nt = Notetype(id: 10, name: "Básico", kind: .standard, css: "",
                          fields: [NoteField(ord: 0, name: "Frente"), NoteField(ord: 1, name: "Reverso")],
                          templates: [CardTemplate(ord: 0, name: "T", questionFormat: "{{Frente}}", answerFormat: "{{Reverso}}")])
        try store.upsertNotetype(nt)
        return 10
    }

    private func clozeNotetype() throws -> Int64 {
        let nt = Notetype(id: 11, name: "Cloze", kind: .cloze, css: "",
                          fields: [NoteField(ord: 0, name: "Texto"), NoteField(ord: 1, name: "Extra")],
                          templates: [CardTemplate(ord: 0, name: "C", questionFormat: "{{cloze:Texto}}", answerFormat: "{{cloze:Texto}}")])
        try store.upsertNotetype(nt)
        return 11
    }

    func testAddNoteGeneratesOneCardForBasic() throws {
        let nt = try basicNotetype()
        let note = try store.addNote(notetypeID: nt, deckID: 1, fields: ["Hola", "Hello"], tags: ["saludo"])
        XCTAssertEqual(try store.cards(forNote: note.id).count, 1)
        XCTAssertTrue(try store.allTags().contains("saludo"))
    }

    func testAddClozeNoteGeneratesCardPerCloze() throws {
        let nt = try clozeNotetype()
        let note = try store.addNote(notetypeID: nt, deckID: 1,
                                     fields: ["{{c1::uno}} y {{c2::dos}}", "extra"], tags: [])
        XCTAssertEqual(try store.cards(forNote: note.id).count, 2)
    }

    func testSearch() throws {
        let nt = try basicNotetype()
        _ = try store.addNote(notetypeID: nt, deckID: 1, fields: ["Fotosíntesis", "Proceso"], tags: ["biología"])
        var filter = CardBrowseFilter()
        filter.text = "fotos"
        XCTAssertEqual(try store.browse(filter).count, 1)
        filter.text = "noexiste"
        XCTAssertEqual(try store.browse(filter).count, 0)
        filter.text = ""
        filter.tag = "biología"
        XCTAssertEqual(try store.browse(filter).count, 1)
    }

    func testDeckCountsNewCards() throws {
        let nt = try basicNotetype()
        let deck = try store.createDeck(name: "Ciencias")
        for i in 0..<5 { _ = try store.addNote(notetypeID: nt, deckID: deck.id, fields: ["P\(i)", "R\(i)"], tags: []) }
        let counts = try store.deckCounts(for: deck)
        XCTAssertEqual(counts.total, 5)
        XCTAssertEqual(counts.newCount, 5)
    }

    func testSuspendAndFavorite() throws {
        let nt = try basicNotetype()
        let note = try store.addNote(notetypeID: nt, deckID: 1, fields: ["A", "B"], tags: [])
        let cardID = try XCTUnwrap(try store.cards(forNote: note.id).first?.id)
        try store.setSuspended(true, cardIDs: [cardID])
        try store.setFavorite(true, cardIDs: [cardID])
        let card = try XCTUnwrap(try store.card(id: cardID))
        XCTAssertTrue(card.suspended)
        XCTAssertTrue(card.favorite)
    }

    func testPersistenceAcrossReopen() throws {
        let subdir = dir.appendingPathComponent("persist")
        let dbURL = subdir.appendingPathComponent("c.sqlite")
        let mediaURL = subdir.appendingPathComponent("media")
        do {
            let s1 = try MemoraStore(databaseURL: dbURL, mediaDirectory: mediaURL)
            let nt = Notetype(id: 10, name: "B", kind: .standard, css: "",
                              fields: [NoteField(ord: 0, name: "F"), NoteField(ord: 1, name: "R")],
                              templates: [CardTemplate(ord: 0, name: "T", questionFormat: "{{F}}", answerFormat: "{{R}}")])
            try s1.upsertNotetype(nt)
            _ = try s1.addNote(notetypeID: 10, deckID: 1, fields: ["persistente", "x"], tags: [])
        } // s1 closes here
        let s2 = try MemoraStore(databaseURL: dbURL, mediaDirectory: mediaURL)
        XCTAssertEqual(try s2.noteCount(), 1, "data must survive reopening the database")
    }

    func testBackupAndRestore() throws {
        let nt = try basicNotetype()
        _ = try store.addNote(notetypeID: nt, deckID: 1, fields: ["respaldo", "x"], tags: ["t"])
        XCTAssertEqual(try store.noteCount(), 1)

        let backupURL = dir.appendingPathComponent("backup.memora")
        try BackupManager.createBackup(store: store, to: backupURL)

        // Delete everything, then restore.
        let onlyNote = try XCTUnwrap(try store.db.query("SELECT id FROM notes") { $0.int(0) }.first)
        try store.deleteNote(id: onlyNote)
        XCTAssertEqual(try store.noteCount(), 0)

        let manifest = try BackupManager.restore(from: backupURL, databaseURL: store.databaseURL, mediaDirectory: store.mediaDirectory)
        XCTAssertEqual(manifest.noteCount, 1)

        let reopened = try MemoraStore(databaseURL: store.databaseURL, mediaDirectory: store.mediaDirectory)
        XCTAssertEqual(try reopened.noteCount(), 1, "restore must bring the note back")
    }

    func testIntegrityCheck() throws {
        XCTAssertEqual(try store.integrityCheck(), "ok")
    }

    func testMediaPathTraversalNeutralised() throws {
        // Path components are stripped so a malicious name cannot escape the
        // media directory; the result is always a bare filename or nil.
        XCTAssertEqual(MemoraStore.sanitizeMediaFilename("../../etc/passwd"), "passwd")
        XCTAssertEqual(MemoraStore.sanitizeMediaFilename("a/b.png"), "b.png")
        XCTAssertEqual(MemoraStore.sanitizeMediaFilename("imagen.png"), "imagen.png")
        XCTAssertNil(MemoraStore.sanitizeMediaFilename(".."))
        XCTAssertNil(MemoraStore.sanitizeMediaFilename(""))
    }
}
