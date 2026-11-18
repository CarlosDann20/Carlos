//
//  Schema.swift
//  Memora
//
//  The SQLite schema for Memora's own collection database, plus a small
//  migration runner. The schema is tuned for the dominant query patterns:
//  building the study queue (deck_id, state, due), listing decks with counts,
//  and browsing/searching notes.
//

import Foundation

enum Schema {
    /// Current app schema version. Bump when adding a migration.
    static let currentVersion = 1

    static let ddl = """
    CREATE TABLE IF NOT EXISTS collection (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        crt           INTEGER NOT NULL,
        rollover_hour INTEGER NOT NULL DEFAULT 4,
        schema_version INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS deck_config (
        id    INTEGER PRIMARY KEY,
        name  TEXT NOT NULL,
        json  TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS decks (
        id        INTEGER PRIMARY KEY,
        name      TEXT NOT NULL,
        parent_id INTEGER,
        config_id INTEGER NOT NULL DEFAULT 1,
        collapsed INTEGER NOT NULL DEFAULT 0,
        filtered  INTEGER NOT NULL DEFAULT 0,
        created   INTEGER NOT NULL DEFAULT 0,
        modified  INTEGER NOT NULL DEFAULT 0
    );
    CREATE UNIQUE INDEX IF NOT EXISTS ix_decks_name ON decks (name);
    CREATE INDEX IF NOT EXISTS ix_decks_parent ON decks (parent_id);

    CREATE TABLE IF NOT EXISTS notetypes (
        id         INTEGER PRIMARY KEY,
        name       TEXT NOT NULL,
        kind       INTEGER NOT NULL DEFAULT 0,
        css        TEXT NOT NULL DEFAULT '',
        latex_pre  TEXT NOT NULL DEFAULT '',
        latex_post TEXT NOT NULL DEFAULT '',
        sort_field INTEGER NOT NULL DEFAULT 0,
        modified   INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS fields (
        notetype_id INTEGER NOT NULL,
        ord         INTEGER NOT NULL,
        name        TEXT NOT NULL,
        rtl         INTEGER NOT NULL DEFAULT 0,
        font        TEXT NOT NULL DEFAULT 'Arial',
        size        INTEGER NOT NULL DEFAULT 20,
        sticky      INTEGER NOT NULL DEFAULT 0,
        description TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (notetype_id, ord)
    );

    CREATE TABLE IF NOT EXISTS templates (
        notetype_id   INTEGER NOT NULL,
        ord           INTEGER NOT NULL,
        name          TEXT NOT NULL,
        qfmt          TEXT NOT NULL,
        afmt          TEXT NOT NULL,
        deck_override INTEGER,
        PRIMARY KEY (notetype_id, ord)
    );

    CREATE TABLE IF NOT EXISTS notes (
        id          INTEGER PRIMARY KEY,
        guid        TEXT NOT NULL,
        notetype_id INTEGER NOT NULL,
        modified    INTEGER NOT NULL DEFAULT 0,
        tags        TEXT NOT NULL DEFAULT '',
        flds        TEXT NOT NULL,
        sfld        TEXT NOT NULL DEFAULT '',
        csum        INTEGER NOT NULL DEFAULT 0,
        search_text TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS ix_notes_guid ON notes (guid);
    CREATE INDEX IF NOT EXISTS ix_notes_csum ON notes (csum);
    CREATE INDEX IF NOT EXISTS ix_notes_notetype ON notes (notetype_id);

    CREATE TABLE IF NOT EXISTS cards (
        id          INTEGER PRIMARY KEY,
        note_id     INTEGER NOT NULL,
        deck_id     INTEGER NOT NULL,
        ord         INTEGER NOT NULL,
        state       INTEGER NOT NULL DEFAULT 0,
        due         INTEGER NOT NULL DEFAULT 0,
        position    INTEGER NOT NULL DEFAULT 0,
        ivl         INTEGER NOT NULL DEFAULT 0,
        reps        INTEGER NOT NULL DEFAULT 0,
        lapses      INTEGER NOT NULL DEFAULT 0,
        learn_step  INTEGER NOT NULL DEFAULT 0,
        stability   REAL,
        difficulty  REAL,
        ease        INTEGER NOT NULL DEFAULT 2500,
        last_review INTEGER,
        suspended   INTEGER NOT NULL DEFAULT 0,
        bury        INTEGER NOT NULL DEFAULT 0,
        favorite    INTEGER NOT NULL DEFAULT 0,
        flags       INTEGER NOT NULL DEFAULT 0,
        odue        INTEGER NOT NULL DEFAULT 0,
        odid        INTEGER NOT NULL DEFAULT 0,
        created     INTEGER NOT NULL DEFAULT 0,
        modified    INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS ix_cards_note ON cards (note_id);
    CREATE INDEX IF NOT EXISTS ix_cards_sched ON cards (deck_id, state, due);
    CREATE INDEX IF NOT EXISTS ix_cards_queue ON cards (deck_id, suspended, bury, state);
    CREATE INDEX IF NOT EXISTS ix_cards_favorite ON cards (favorite);
    CREATE INDEX IF NOT EXISTS ix_cards_position ON cards (deck_id, position);

    CREATE TABLE IF NOT EXISTS revlog (
        id           INTEGER PRIMARY KEY,
        card_id      INTEGER NOT NULL,
        rating       INTEGER NOT NULL,
        ivl          INTEGER NOT NULL DEFAULT 0,
        last_ivl     INTEGER NOT NULL DEFAULT 0,
        ease         INTEGER NOT NULL DEFAULT 0,
        stability    REAL,
        difficulty   REAL,
        state_before INTEGER NOT NULL DEFAULT 0,
        kind         INTEGER NOT NULL DEFAULT 1,
        time_ms      INTEGER NOT NULL DEFAULT 0,
        reviewed_at  INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS ix_revlog_card ON revlog (card_id);
    CREATE INDEX IF NOT EXISTS ix_revlog_time ON revlog (reviewed_at);

    CREATE TABLE IF NOT EXISTS media (
        filename TEXT PRIMARY KEY,
        size     INTEGER NOT NULL DEFAULT 0,
        sha1     TEXT NOT NULL DEFAULT ''
    );

    CREATE TABLE IF NOT EXISTS tags (
        name TEXT PRIMARY KEY
    );
    """

    static func migrate(_ db: SQLiteDatabase) throws {
        try db.exec(ddl)
    }
}
