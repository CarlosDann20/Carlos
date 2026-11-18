//
//  MediaReferences.swift
//  Memora
//
//  Extracts media filenames referenced by note/template content:
//  `<img src="...">`, `<source src="...">`, `<audio>`/`<video>` and Anki's
//  `[sound:...]` syntax. Used for media accounting and to resolve files when
//  rendering a card.
//

import Foundation

public enum MediaReferences {

    public static func extract(from html: String) -> Set<String> {
        var names = Set<String>()
        names.formUnion(matches(in: html, pattern: #"\[sound:([^\]]+)\]"#, group: 1))
        names.formUnion(matches(in: html, pattern: #"(?:src|data-src)\s*=\s*"([^"]+)""#, group: 1))
        names.formUnion(matches(in: html, pattern: #"(?:src|data-src)\s*=\s*'([^']+)'"#, group: 1))
        // Keep only local references (strip any path, ignore remote URLs).
        return Set(names.compactMap { normalize($0) })
    }

    private static func normalize(_ ref: String) -> String? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("data:") {
            return nil
        }
        // Percent-decode and take the last path component.
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let name = (decoded as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func matches(in text: String, pattern: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var result: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return }
            result.append(String(text[r]))
        }
        return result
    }
}
