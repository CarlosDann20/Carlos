//
//  CardRenderer.swift
//  Memora
//
//  Produces the question/answer HTML for a card from its note + note type,
//  and wraps it in a full HTML document (with the note type's CSS) suitable
//  for display in a WKWebView whose baseURL is the media directory, so that
//  `<img src="...">` and audio resolve to local files. No remote content is
//  ever loaded.
//

import Foundation

public struct RenderedCard: Sendable {
    public var questionHTML: String
    public var answerHTML: String
    public var css: String
    public var warnings: [RenderWarning]
}

public enum CardRenderer {

    public static func render(card: Card, note: Note, notetype: Notetype, deckName: String = "") -> RenderedCard {
        var fields: [String: String] = [:]
        for field in notetype.fields {
            let value = note.fields.indices.contains(field.ord) ? note.fields[field.ord] : ""
            fields[field.name] = value
        }
        // Special fields Anki exposes to templates.
        fields["Tags"] = note.tags.joined(separator: " ")
        fields["Type"] = notetype.name
        fields["Deck"] = deckName
        fields["Subdeck"] = deckName.components(separatedBy: Deck.separator).last ?? deckName

        let isCloze = notetype.kind == .cloze
        let template: CardTemplate
        if isCloze {
            template = notetype.templates.first ?? CardTemplate(ord: 0, name: "Cloze", questionFormat: "{{cloze:\(notetype.fields.first?.name ?? "Text")}}", answerFormat: "{{FrontSide}}")
        } else if notetype.templates.indices.contains(card.templateOrd) {
            template = notetype.templates[card.templateOrd]
        } else {
            template = notetype.templates.first ?? CardTemplate(ord: 0, name: "Card", questionFormat: note.fields.first ?? "", answerFormat: "")
        }
        let clozeOrd = isCloze ? card.templateOrd + 1 : 1

        var renderer = TemplateRenderer()
        let qContext = TemplateRenderer.Context(fields: fields, frontSide: "", isCloze: isCloze, clozeOrd: clozeOrd)
        let question = renderer.render(template.questionFormat, context: qContext, revealCloze: false)

        let aContext = TemplateRenderer.Context(fields: fields, frontSide: question, isCloze: isCloze, clozeOrd: clozeOrd)
        let answer = renderer.render(template.answerFormat, context: aContext, revealCloze: true)

        return RenderedCard(questionHTML: question, answerHTML: answer, css: notetype.css, warnings: renderer.warnings)
    }

    /// Build a complete HTML document for the WebView.
    public static func document(body: String, css: String, dark: Bool, textScale: Double = 1.0) -> String {
        let nightClass = dark ? " nightMode night_mode" : ""
        let baseCSS = """
        :root { color-scheme: \(dark ? "dark" : "light"); }
        html, body { margin: 0; padding: 0; }
        body {
            font-family: -apple-system, "SF Pro Rounded", "SF Pro", system-ui, sans-serif;
            font-size: \(Int(20 * textScale))px;
            line-height: 1.5;
            padding: 20px;
            -webkit-text-size-adjust: 100%;
            background: transparent;
            color: \(dark ? "#f2f2f7" : "#1c1c1e");
        }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        .memora-audio { width: 100%; max-width: 360px; margin: 10px auto; display: block; }
        .cloze { font-weight: 700; color: \(dark ? "#5ea1ff" : "#0a66ff"); }
        .memora-hint { color: \(dark ? "#5ea1ff" : "#0a66ff"); text-decoration: underline; cursor: pointer; }
        hr#answer { border: none; border-top: 1px solid \(dark ? "#3a3a3c" : "#d1d1d6"); margin: 18px 0; }
        """
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>\(baseCSS)\n/* --- Note type CSS --- */\n\(css)</style>
        </head>
        <body class="card\(nightClass)">
        \(body)
        </body>
        </html>
        """
    }
}
