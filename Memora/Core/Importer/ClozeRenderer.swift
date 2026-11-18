//
//  ClozeRenderer.swift
//  Memora
//
//  Renders Anki cloze deletions: `{{c1::answer}}` or `{{c1::answer::hint}}`.
//  For the active cloze number the answer is hidden on the question side
//  (shown as the hint or "[...]") and revealed on the answer side; other
//  clozes always show their text. Matches Anki's behaviour.
//

import Foundation

public enum ClozeRenderer {

    public static func render(_ field: String, activeOrd: Int, reveal: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{c(\d+)::([\s\S]*?)\}\}"#) else { return field }
        let ns = field as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: field, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let num = Int(ns.substring(with: match.range(at: 1))) ?? -1
            let content = ns.substring(with: match.range(at: 2))
            let (answer, hint) = splitHint(content)
            if num == activeOrd {
                if reveal {
                    result += "<span class=\"cloze\">\(answer)</span>"
                } else {
                    let placeholder = hint ?? "..."
                    result += "<span class=\"cloze\">[\(placeholder)]</span>"
                }
            } else {
                result += answer
            }
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// The set of cloze numbers present in a field (used to decide how many
    /// cards a cloze note generates).
    public static func clozeNumbers(in field: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{c(\d+)::"#) else { return [] }
        let ns = field as NSString
        var nums = Set<Int>()
        for match in regex.matches(in: field, range: NSRange(location: 0, length: ns.length)) {
            if let n = Int(ns.substring(with: match.range(at: 1))) { nums.insert(n) }
        }
        return nums
    }

    private static func splitHint(_ content: String) -> (String, String?) {
        if let range = content.range(of: "::") {
            let answer = String(content[..<range.lowerBound])
            let hint = String(content[range.upperBound...])
            return (answer, hint.isEmpty ? nil : hint)
        }
        return (content, nil)
    }
}
