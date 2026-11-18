//
//  MemoraStore+Notetypes.swift
//  Memora
//

import Foundation

extension MemoraStore {

    public func upsertNotetype(_ nt: Notetype) throws {
        try db.transaction {
            try db.run("""
                INSERT INTO notetypes (id, name, kind, css, latex_pre, latex_post, sort_field, modified)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name, kind = excluded.kind, css = excluded.css,
                  latex_pre = excluded.latex_pre, latex_post = excluded.latex_post,
                  sort_field = excluded.sort_field, modified = excluded.modified
                """, [.integer(nt.id), .text(nt.name), .integer(Int64(nt.kind.rawValue)),
                      .text(nt.css), .text(nt.latexPre), .text(nt.latexPost),
                      .integer(Int64(nt.sortFieldIndex)), .integer(nt.modified)])
            try db.run("DELETE FROM fields WHERE notetype_id = ?", [.integer(nt.id)])
            for f in nt.fields {
                try db.run("""
                    INSERT INTO fields (notetype_id, ord, name, rtl, font, size, sticky, description)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.integer(nt.id), .integer(Int64(f.ord)), .text(f.name),
                          .integer(f.rightToLeft ? 1 : 0), .text(f.fontFamily),
                          .integer(Int64(f.fontSize)), .integer(f.sticky ? 1 : 0), .text(f.descriptionText)])
            }
            try db.run("DELETE FROM templates WHERE notetype_id = ?", [.integer(nt.id)])
            for t in nt.templates {
                try db.run("""
                    INSERT INTO templates (notetype_id, ord, name, qfmt, afmt, deck_override)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, [.integer(nt.id), .integer(Int64(t.ord)), .text(t.name),
                          .text(t.questionFormat), .text(t.answerFormat),
                          t.deckOverrideID.map { .integer($0) } ?? .null])
            }
        }
    }

    public func notetype(id: Int64) throws -> Notetype? {
        let base = try db.query("""
            SELECT id, name, kind, css, latex_pre, latex_post, sort_field, modified
            FROM notetypes WHERE id = ?
            """, [.integer(id)]) { row -> (Int64, String, Int, String, String, String, Int, Int64) in
            (row.int(0), row.string(1), Int(row.int(2)), row.string(3), row.string(4), row.string(5), Int(row.int(6)), row.int(7))
        }.first
        guard let base else { return nil }

        let fields = try db.query("""
            SELECT ord, name, rtl, font, size, sticky, description FROM fields
            WHERE notetype_id = ? ORDER BY ord
            """, [.integer(id)]) { row in
            NoteField(ord: Int(row.int(0)), name: row.string(1), rightToLeft: row.int(2) != 0,
                      fontFamily: row.string(3), fontSize: Int(row.int(4)),
                      sticky: row.int(5) != 0, descriptionText: row.string(6))
        }
        let templates = try db.query("""
            SELECT ord, name, qfmt, afmt, deck_override FROM templates
            WHERE notetype_id = ? ORDER BY ord
            """, [.integer(id)]) { row in
            CardTemplate(ord: Int(row.int(0)), name: row.string(1), questionFormat: row.string(2),
                         answerFormat: row.string(3), deckOverrideID: row.intOptional(4))
        }
        return Notetype(id: base.0, name: base.1, kind: NotetypeKind(rawValue: base.2) ?? .standard,
                        css: base.3, fields: fields, templates: templates,
                        latexPre: base.4, latexPost: base.5, sortFieldIndex: base.6, modified: base.7)
    }

    public func allNotetypes() throws -> [Notetype] {
        let ids = try db.query("SELECT id FROM notetypes ORDER BY name") { $0.int(0) }
        return try ids.compactMap { try notetype(id: $0) }
    }

    public func notetypeExists(id: Int64) throws -> Bool {
        try db.scalarInt("SELECT COUNT(*) FROM notetypes WHERE id = ?", [.integer(id)]) > 0
    }
}
