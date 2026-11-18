//
//  TemplateRenderer.swift
//  Memora
//
//  Renders Anki card templates: field substitution, {{FrontSide}},
//  conditionals ({{#Field}} / {{^Field}}), the common field filters
//  (text:, hint:, cloze:) and cloze deletions. Unknown filters fall back to
//  the raw field value and record a warning, so a card is never shown blank
//  and no content is silently lost (per the spec).
//

import Foundation

public struct RenderWarning: Sendable, Hashable {
    public var message: String
}

public struct TemplateRenderer {

    public struct Context {
        public var fields: [String: String]
        public var frontSide: String
        public var isCloze: Bool
        public var clozeOrd: Int   // active cloze number (1-based)

        public init(fields: [String: String], frontSide: String = "", isCloze: Bool = false, clozeOrd: Int = 1) {
            self.fields = fields
            self.frontSide = frontSide
            self.isCloze = isCloze
            self.clozeOrd = clozeOrd
        }
    }

    public private(set) var warnings: [RenderWarning] = []

    public init() {}

    public mutating func render(_ template: String, context: Context, revealCloze: Bool) -> String {
        var out = resolveConditionals(template, context: context)
        out = replaceTokens(out, context: context, revealCloze: revealCloze)
        out = convertSound(out)
        return out
    }

    // MARK: - Conditionals {{#Field}}...{{/Field}} and {{^Field}}...{{/Field}}

    private func resolveConditionals(_ input: String, context: Context) -> String {
        var text = input
        let pattern = #"\{\{([#^])([^{}]+)\}\}([\s\S]*?)\{\{/\2\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var guardCount = 0
        while guardCount < 50 {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let full = Range(match.range, in: text),
                  let typeR = Range(match.range(at: 1), in: text),
                  let nameR = Range(match.range(at: 2), in: text),
                  let bodyR = Range(match.range(at: 3), in: text) else { break }
            let isPositive = text[typeR] == "#"
            let field = String(text[nameR]).trimmingCharacters(in: .whitespaces)
            let body = String(text[bodyR])
            let nonEmpty = !(context.fields[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let keep = isPositive ? nonEmpty : !nonEmpty
            text.replaceSubrange(full, with: keep ? body : "")
            guardCount += 1
        }
        return text
    }

    // MARK: - Token replacement

    private mutating func replaceTokens(_ input: String, context: Context, revealCloze: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([^{}#/^][^{}]*)\}\}"#) else { return input }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        var result = ""
        var last = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let token = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            result += value(for: token, context: context, revealCloze: revealCloze)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private mutating func value(for token: String, context: Context, revealCloze: Bool) -> String {
        if token == "FrontSide" { return context.frontSide }
        var parts = token.components(separatedBy: ":")
        let fieldName = parts.removeLast().trimmingCharacters(in: .whitespaces)
        let filters = parts.map { $0.trimmingCharacters(in: .whitespaces) } // outermost first

        let raw: String
        if fieldName == "FrontSide" { raw = context.frontSide }
        else { raw = context.fields[fieldName] ?? "" }

        if filters.isEmpty { return raw }

        var value = raw
        // Apply filters inner-to-outer (right-to-left).
        for filter in filters.reversed() {
            value = applyFilter(filter, to: value, context: context, revealCloze: revealCloze)
        }
        return value
    }

    private mutating func applyFilter(_ filter: String, to value: String, context: Context, revealCloze: Bool) -> String {
        switch filter {
        case "text":
            return TextStripping.stripHTML(value)
        case "cloze":
            return ClozeRenderer.render(value, activeOrd: context.clozeOrd, reveal: revealCloze)
        case "hint":
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
            let id = "hint-\(abs(value.hashValue))"
            return "<a class=\"memora-hint\" href=\"#\" onclick=\"document.getElementById('\(id)').style.display='inline';this.style.display='none';return false;\">Mostrar pista</a><span id=\"\(id)\" style=\"display:none\">\(value)</span>"
        case "type":
            warnings.append(RenderWarning(message: "El campo de entrada «type:\(filter)» no es compatible; se muestra el contenido del campo."))
            return value
        default:
            warnings.append(RenderWarning(message: "Filtro de plantilla no compatible: «\(filter)». Se muestra el campo sin transformar."))
            return value
        }
    }

    // MARK: - Sound

    /// Convert Anki `[sound:file]` markup into an HTML5 audio element that the
    /// WebView can play from the media directory (resolved via baseURL).
    private func convertSound(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[sound:([^\]]+)\]"#) else { return input }
        let ns = input as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let file = ns.substring(with: match.range(at: 1))
            let escaped = file.replacingOccurrences(of: "\"", with: "&quot;")
            result += "<audio controls preload=\"none\" class=\"memora-audio\" src=\"\(escaped)\"></audio>"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
