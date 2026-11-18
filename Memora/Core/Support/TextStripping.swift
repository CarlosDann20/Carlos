//
//  TextStripping.swift
//  Memora
//
//  Helpers to derive plain, searchable/sortable text from HTML field content.
//  Used for the sort field, duplicate detection and search indexing. This is
//  a pragmatic stripper (not a full HTML parser) that mirrors how Anki reduces
//  fields to comparable text.
//

import Foundation

public enum TextStripping {
    /// Remove HTML tags, decode a few common entities, drop media references,
    /// and collapse whitespace.
    public static func stripHTML(_ input: String) -> String {
        var s = input
        // Remove <style>…</style> and <script>…</script> blocks.
        s = removeBlocks(in: s, tag: "style")
        s = removeBlocks(in: s, tag: "script")
        // Replace <br> and block tags with spaces.
        s = s.replacingOccurrences(of: "<br>", with: " ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: " ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: " ", options: .caseInsensitive)
        // Strip all remaining tags.
        s = stripTags(s)
        // Decode a handful of entities.
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        // Collapse whitespace.
        let collapsed = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return collapsed.joined(separator: " ")
    }

    /// Normalised key for duplicate detection: stripped, lowercased, trimmed.
    public static func normalizedForDedup(_ field: String) -> String {
        stripHTML(field).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Anki-compatible field checksum: first 8 hex chars of SHA1 of the
    /// stripped first field, as a 32-bit integer.
    public static func fieldChecksum(_ firstField: String) -> Int64 {
        let stripped = stripHTML(firstField)
        let digest = SHA1.hash(Data(stripped.utf8))
        // First 4 bytes as big-endian unsigned int (matches Anki's csum).
        var value: Int64 = 0
        for i in 0..<4 { value = (value << 8) | Int64(digest[i]) }
        return value
    }

    private static func stripTags(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var insideTag = false
        for ch in input {
            if ch == "<" { insideTag = true; continue }
            if ch == ">" { insideTag = false; result.append(" "); continue }
            if !insideTag { result.append(ch) }
        }
        return result
    }

    private static func removeBlocks(in input: String, tag: String) -> String {
        var s = input
        while let openRange = s.range(of: "<\(tag)", options: .caseInsensitive) {
            if let closeRange = s.range(of: "</\(tag)>", options: .caseInsensitive, range: openRange.lowerBound..<s.endIndex) {
                s.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                s.removeSubrange(openRange.lowerBound..<s.endIndex)
                break
            }
        }
        return s
    }
}
