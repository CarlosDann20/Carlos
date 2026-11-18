//
//  RenderingTests.swift
//  MemoraTests
//
//  Cloze rendering, template substitution/conditionals/filters, and end-to-end
//  card rendering.
//

import XCTest
@testable import Memora

final class RenderingTests: XCTestCase {

    func testClozeHidesActiveAndShowsOthers() {
        let field = "La capital de España es {{c1::Madrid}} y de Francia {{c2::París}}."
        let q1 = ClozeRenderer.render(field, activeOrd: 1, reveal: false)
        XCTAssertTrue(q1.contains("[...]"))
        XCTAssertFalse(q1.contains("Madrid"))
        XCTAssertTrue(q1.contains("París"), "non-active cloze stays visible")

        let a1 = ClozeRenderer.render(field, activeOrd: 1, reveal: true)
        XCTAssertTrue(a1.contains("Madrid"))
    }

    func testClozeHint() {
        let field = "El símbolo es {{c1::Fe::hierro}}"
        let q = ClozeRenderer.render(field, activeOrd: 1, reveal: false)
        XCTAssertTrue(q.contains("[hierro]"))
        XCTAssertFalse(q.contains("Fe<"))
    }

    func testClozeNumbers() {
        XCTAssertEqual(ClozeRenderer.clozeNumbers(in: "{{c1::a}} {{c3::b}}"), [1, 3])
    }

    func testTemplateFieldSubstitution() {
        var r = TemplateRenderer()
        let ctx = TemplateRenderer.Context(fields: ["Front": "Hola", "Back": "Hello"])
        let q = r.render("{{Front}}", context: ctx, revealCloze: false)
        XCTAssertEqual(q.trimmingCharacters(in: .whitespaces), "Hola")
    }

    func testTemplateConditionals() {
        var r = TemplateRenderer()
        let withExtra = TemplateRenderer.Context(fields: ["Extra": "nota"])
        XCTAssertTrue(r.render("{{#Extra}}tiene{{/Extra}}", context: withExtra, revealCloze: false).contains("tiene"))
        var r2 = TemplateRenderer()
        let noExtra = TemplateRenderer.Context(fields: ["Extra": ""])
        XCTAssertFalse(r2.render("{{#Extra}}tiene{{/Extra}}", context: noExtra, revealCloze: false).contains("tiene"))
        var r3 = TemplateRenderer()
        XCTAssertTrue(r3.render("{{^Extra}}vacío{{/Extra}}", context: noExtra, revealCloze: false).contains("vacío"))
    }

    func testFrontSideOnAnswer() {
        var r = TemplateRenderer()
        let ctx = TemplateRenderer.Context(fields: ["Back": "respuesta"], frontSide: "PREGUNTA")
        let a = r.render("{{FrontSide}}<hr>{{Back}}", context: ctx, revealCloze: false)
        XCTAssertTrue(a.contains("PREGUNTA"))
        XCTAssertTrue(a.contains("respuesta"))
    }

    func testUnknownFilterWarnsButKeepsContent() {
        var r = TemplateRenderer()
        let ctx = TemplateRenderer.Context(fields: ["Front": "contenido"])
        let out = r.render("{{desconocido:Front}}", context: ctx, revealCloze: false)
        XCTAssertTrue(out.contains("contenido"), "content must not be lost")
        XCTAssertFalse(r.warnings.isEmpty, "unsupported filter should warn")
    }

    func testSoundConvertedToAudio() {
        var r = TemplateRenderer()
        let ctx = TemplateRenderer.Context(fields: ["F": "[sound:a.mp3]"])
        let out = r.render("{{F}}", context: ctx, revealCloze: false)
        XCTAssertTrue(out.contains("<audio"))
        XCTAssertTrue(out.contains("a.mp3"))
    }

    func testCardRendererBasic() {
        let nt = Notetype(id: 1, name: "Básico", kind: .standard, css: ".card{}",
                          fields: [NoteField(ord: 0, name: "Frente"), NoteField(ord: 1, name: "Reverso")],
                          templates: [CardTemplate(ord: 0, name: "T", questionFormat: "{{Frente}}",
                                                   answerFormat: "{{FrontSide}}<hr>{{Reverso}}")])
        let note = Note(id: 1, guid: "g", notetypeID: 1, modified: 0, fields: ["¿Capital?", "París"], tags: [], checksum: 0)
        let card = Card(id: 1, noteID: 1, deckID: 1, templateOrd: 0)
        let rc = CardRenderer.render(card: card, note: note, notetype: nt)
        XCTAssertTrue(rc.questionHTML.contains("Capital"))
        XCTAssertTrue(rc.answerHTML.contains("París"))
        XCTAssertTrue(rc.answerHTML.contains("Capital"), "answer includes FrontSide")
    }

    func testDocumentWrappsCSSAndBody() {
        let doc = CardRenderer.document(body: "<b>hola</b>", css: ".card{color:red}", dark: true, textScale: 1.2)
        XCTAssertTrue(doc.contains("<!DOCTYPE html>"))
        XCTAssertTrue(doc.contains(".card{color:red}"))
        XCTAssertTrue(doc.contains("nightMode"))
        XCTAssertTrue(doc.contains("hola"))
    }
}
