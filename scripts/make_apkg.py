#!/usr/bin/env python3
"""
Build real .apkg fixtures (Anki legacy schema-11 format) for validating and
testing Memora's importer. Also builds a v3-stub to exercise version detection.

Outputs into MemoraTests/Fixtures/:
    basic.apkg   - legacy2, Basic + Cloze notes, media, review+FSRS scheduling
    legacy1.apkg - legacy1 (collection.anki2), one basic note
    large.apkg   - legacy2, 4000 basic notes (performance fixture)
    v3stub.apkg  - meta protobuf version=3 (must be detected & rejected)
"""
import hashlib, json, os, sqlite3, struct, sys, tempfile, zipfile

FIX = os.path.join(os.path.dirname(__file__), "..", "MemoraTests", "Fixtures")
os.makedirs(FIX, exist_ok=True)
US = "\x1f"  # field separator

BASIC_MID = 1607000000000
CLOZE_MID = 1607000000001
SUBDECK_ID = 1607000001000

def csum(first_field):
    return int.from_bytes(hashlib.sha1(first_field.encode()).digest()[:4], "big")

SCHEMA = """
CREATE TABLE col (id integer primary key, crt integer, mod integer, scm integer, ver integer,
 dty integer, usn integer, ls integer, conf text, models text, decks text, dconf text, tags text);
CREATE TABLE notes (id integer primary key, guid text, mid integer, mod integer, usn integer,
 tags text, flds text, sfld integer, csum integer, flags integer, data text);
CREATE TABLE cards (id integer primary key, nid integer, did integer, ord integer, mod integer,
 usn integer, type integer, queue integer, due integer, ivl integer, factor integer, reps integer,
 lapses integer, left integer, odue integer, odid integer, flags integer, data text);
CREATE TABLE revlog (id integer primary key, cid integer, usn integer, ease integer, ivl integer,
 lastIvl integer, factor integer, time integer, type integer);
CREATE TABLE graves (usn integer, oid integer, type integer);
"""

def models_json():
    return json.dumps({
        str(BASIC_MID): {
            "id": BASIC_MID, "name": "Básico", "type": 0,
            "css": ".card{font-family:arial;font-size:20px;text-align:center;color:#fff;background:#111}",
            "flds": [{"name": "Frente", "ord": 0}, {"name": "Reverso", "ord": 1}],
            "tmpls": [{"name": "Tarjeta 1", "ord": 0,
                       "qfmt": "{{Frente}}",
                       "afmt": "{{FrontSide}}\n\n<hr id=answer>\n\n{{Reverso}}"}],
            "sortf": 0, "latexPre": "", "latexPost": ""
        },
        str(CLOZE_MID): {
            "id": CLOZE_MID, "name": "Omisión (Cloze)", "type": 1,
            "css": ".card{font-family:arial;font-size:20px;color:#fff;background:#111}.cloze{font-weight:bold;color:#4da6ff}",
            "flds": [{"name": "Texto", "ord": 0}, {"name": "Extra", "ord": 1}],
            "tmpls": [{"name": "Omisión", "ord": 0,
                       "qfmt": "{{cloze:Texto}}",
                       "afmt": "{{cloze:Texto}}<br>\n{{Extra}}"}],
            "sortf": 0, "latexPre": "", "latexPost": ""
        }
    }, ensure_ascii=False)

def decks_json():
    return json.dumps({
        "1": {"id": 1, "name": "Default", "conf": 1, "dyn": 0},
        str(SUBDECK_ID): {"id": SUBDECK_ID, "name": "Español::Verbos", "conf": 1, "dyn": 0},
    }, ensure_ascii=False)

def dconf_json():
    return json.dumps({
        "1": {"id": 1, "name": "Predeterminada",
              "new": {"perDay": 20, "delays": [1, 10], "initialFactor": 2500},
              "rev": {"perDay": 200, "maxIvl": 36500, "ivlFct": 1.0, "hardFactor": 1.2},
              "lapse": {"delays": [10], "mult": 0.0, "leechFails": 8, "leechAction": 0}}
    }, ensure_ascii=False)

def new_col(con, crt=1600000000):
    con.executescript(SCHEMA)
    con.execute("INSERT INTO col VALUES (1,?,?,?,11,0,-1,0,?,?,?,?,?)",
                (crt, crt * 1000, crt * 1000, "{}", models_json(), decks_json(), dconf_json(), "{}"))

def add_note(con, nid, mid, flds, tags="", data=""):
    first = flds.split(US)[0]
    con.execute("INSERT INTO notes VALUES (?,?,?,?,-1,?,?,?,?,0,?)",
                (nid, f"g{nid}", mid, nid, (" "+tags+" ") if tags else "", flds, first, csum(first), data))

def add_card(con, cid, nid, did, ord, ctype=0, queue=0, due=0, ivl=0, factor=2500,
             reps=0, lapses=0, data=""):
    con.execute("INSERT INTO cards VALUES (?,?,?,?,?,-1,?,?,?,?,?,?,?,0,0,0,0,?)",
                (cid, nid, did, ord, nid, ctype, queue, due, ivl, factor, reps, lapses, data))

def add_revlog(con, rid, cid, ease, ivl, lastIvl, factor, time, rtype):
    con.execute("INSERT INTO revlog VALUES (?,?,-1,?,?,?,?,?,?)",
                (rid, cid, ease, ivl, lastIvl, factor, time, rtype))

PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d49444154789c636060606000000005000157b2b1c40000000049454e44ae426082")

def write_zip(path, col_name, files):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, content in files.items():
            if isinstance(content, str):
                content = content.encode("utf-8")
            z.writestr(name, content)

def build_basic():
    with tempfile.TemporaryDirectory() as td:
        dbp = os.path.join(td, "c.anki2")
        con = sqlite3.connect(dbp); new_col(con)
        # Basic note with media reference
        add_note(con, 1001, BASIC_MID, "¿Capital de Francia?<br><img src=\"img.png\">" + US + "París", tags="geografía")
        add_card(con, 2001, 1001, SUBDECK_ID, 0, ctype=0, queue=0, due=1)
        # Basic note already in review with FSRS memory state
        add_note(con, 1002, BASIC_MID, "Perro" + US + "Dog", tags="idiomas")
        add_card(con, 2002, 1002, 1, 0, ctype=2, queue=2, due=5, ivl=12, factor=2600,
                 reps=4, lapses=1, data=json.dumps({"s": 12.34, "d": 5.67}))
        # Cloze note -> 1 card (c1)
        add_note(con, 1003, CLOZE_MID, "La capital de España es {{c1::Madrid}}." + US + "Dato extra", tags="geografía")
        add_card(con, 2003, 1003, SUBDECK_ID, 0, ctype=0, queue=0, due=2)
        # A couple of revlog rows
        add_revlog(con, 1600000000001, 2002, 3, 12, 7, 2600, 4200, 1)
        add_revlog(con, 1600000000002, 2002, 2, 7, 4, 2550, 6100, 1)
        con.commit(); con.close()
        with open(dbp, "rb") as f: dbbytes = f.read()
        media = {"0": "img.png"}
        write_zip(os.path.join(FIX, "basic.apkg"), "collection.anki21",
                  {"collection.anki21": dbbytes, "media": json.dumps(media), "0": PNG})
    print("built basic.apkg")

def build_legacy1():
    with tempfile.TemporaryDirectory() as td:
        dbp = os.path.join(td, "c.anki2")
        con = sqlite3.connect(dbp); new_col(con)
        add_note(con, 3001, BASIC_MID, "Gato" + US + "Cat")
        add_card(con, 4001, 3001, 1, 0)
        con.commit(); con.close()
        with open(dbp, "rb") as f: dbbytes = f.read()
        write_zip(os.path.join(FIX, "legacy1.apkg"), "collection.anki2",
                  {"collection.anki2": dbbytes, "media": "{}"})
    print("built legacy1.apkg")

def build_large(n=4000):
    with tempfile.TemporaryDirectory() as td:
        dbp = os.path.join(td, "c.anki2")
        con = sqlite3.connect(dbp); new_col(con)
        for i in range(n):
            nid = 500000 + i
            add_note(con, nid, BASIC_MID, f"Pregunta {i}" + US + f"Respuesta {i}", tags="masivo")
            add_card(con, 600000 + i, nid, 1, 0, due=i)
        con.commit(); con.close()
        with open(dbp, "rb") as f: dbbytes = f.read()
        write_zip(os.path.join(FIX, "large.apkg"), "collection.anki21",
                  {"collection.anki21": dbbytes, "media": "{}"})
    print(f"built large.apkg ({n} notes)")

def build_v3stub():
    # meta protobuf: field 1 (version) = 3  ->  tag 0x08, value 0x03
    meta = b"\x08\x03"
    write_zip(os.path.join(FIX, "v3stub.apkg"), "collection.anki21b",
              {"meta": meta, "collection.anki21b": b"\x28\xb5\x2f\xfd" + b"\x00" * 16})
    print("built v3stub.apkg")

if __name__ == "__main__":
    build_basic(); build_legacy1(); build_large(); build_v3stub()
    print("fixtures in", os.path.abspath(FIX))
