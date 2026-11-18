#!/usr/bin/env python3
"""
Validate Memora's .apkg format handling by mirroring the Swift importer's
parsing logic (AnkiPackage.detectVersion / parseMetaVersion, AnkiCollectionReader,
field splitting, media map) and asserting against the generated fixtures.
"""
import json, os, sqlite3, tempfile, zipfile, sys

FIX = os.path.join(os.path.dirname(__file__), "..", "MemoraTests", "Fixtures")
US = "\x1f"
fails = 0

def check(cond, msg):
    global fails
    status = "ok " if cond else "FAIL"
    if not cond: fails += 1
    print(f"  [{status}] {msg}")

def parse_meta_version(data: bytes) -> int:
    # Mirror of AnkiPackage.parseMetaVersion (field 1, varint).
    i = 0
    while i < len(data):
        tag = data[i]; i += 1
        field = tag >> 3; wire = tag & 7
        if field == 1 and wire == 0:
            val = 0; shift = 0
            while i < len(data):
                b = data[i]; i += 1
                val |= (b & 0x7f) << shift
                if not (b & 0x80): break
                shift += 7
            return val
        else:
            if wire == 0:
                while i < len(data) and (data[i] & 0x80): i += 1
                i += 1
            elif wire == 2:
                ln = data[i]; i += 1; i += ln
            elif wire == 5: i += 4
            elif wire == 1: i += 8
            else: return 0
    return 0

def detect_version(z):
    names = set(z.namelist())
    if "meta" in names:
        return parse_meta_version(z.read("meta"))
    if "collection.anki21" in names: return 2
    if "collection.anki2" in names: return 1
    return 0

def open_collection(z, version):
    name = {1: "collection.anki2", 2: "collection.anki21", 3: "collection.anki21b"}[version]
    with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as tf:
        tf.write(z.read(name)); path = tf.name
    return sqlite3.connect(path), path

def read_apkg(path):
    z = zipfile.ZipFile(path)
    version = detect_version(z)
    result = {"version": version}
    if version == 3:
        return result  # Swift rejects; nothing else to read
    con, tmp = open_collection(z, version)
    cur = con.cursor()
    crt, models, decks, dconf = cur.execute("SELECT crt, models, decks, dconf FROM col").fetchone()
    result["models"] = json.loads(models)
    result["decks"] = json.loads(decks)
    notes = cur.execute("SELECT id, guid, mid, tags, flds FROM notes").fetchall()
    result["notes"] = [{"id": n[0], "guid": n[1], "mid": n[2], "tags": n[3],
                        "fields": n[4].split(US)} for n in notes]
    cards = cur.execute("SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses, data FROM cards").fetchall()
    result["cards"] = [{"id": c[0], "nid": c[1], "did": c[2], "ord": c[3], "type": c[4],
                        "queue": c[5], "due": c[6], "ivl": c[7], "factor": c[8],
                        "reps": c[9], "lapses": c[10], "data": c[11]} for c in cards]
    try:
        result["revlog"] = cur.execute("SELECT id, cid, ease FROM revlog").fetchall()
    except sqlite3.OperationalError:
        result["revlog"] = []
    if "media" in z.namelist():
        try: result["media"] = json.loads(z.read("media"))
        except Exception: result["media"] = {}
    con.close(); os.unlink(tmp)
    return result

def main():
    print("meta varint parse: version(b'\\x08\\x03') =", parse_meta_version(b"\x08\x03"))
    check(parse_meta_version(b"\x08\x03") == 3, "meta protobuf version parsed as 3")
    check(parse_meta_version(b"\x08\x01") == 1, "meta protobuf version parsed as 1")

    print("\nbasic.apkg")
    b = read_apkg(os.path.join(FIX, "basic.apkg"))
    check(b["version"] == 2, f"detected legacy2 (got {b['version']})")
    check(len(b["models"]) == 2, f"2 note types (got {len(b['models'])})")
    check(len(b["decks"]) == 2, f"2 decks (got {len(b['decks'])})")
    check(len(b["notes"]) == 3, f"3 notes (got {len(b['notes'])})")
    check(len(b["cards"]) == 3, f"3 cards (got {len(b['cards'])})")
    check(len(b["revlog"]) == 2, f"2 revlog rows (got {len(b['revlog'])})")
    check(b["media"] == {"0": "img.png"}, f"media map correct (got {b['media']})")
    cloze = [n for n in b["notes"] if "{{c1::" in n["fields"][0]]
    check(len(cloze) == 1 and "Madrid" in cloze[0]["fields"][0], "cloze note present with c1::Madrid")
    fsrs = [c for c in b["cards"] if c["data"] and '"s"' in c["data"]]
    check(len(fsrs) == 1 and json.loads(fsrs[0]["data"]).get("s") == 12.34, "FSRS memory (s=12.34) present in card data")
    basic_note = [n for n in b["notes"] if n["fields"][0].startswith("¿Capital")][0]
    check(len(basic_note["fields"]) == 2, "basic note has 2 fields split by 0x1f")
    check("img.png" in basic_note["fields"][0], "media reference preserved in field")

    print("\nlegacy1.apkg")
    l1 = read_apkg(os.path.join(FIX, "legacy1.apkg"))
    check(l1["version"] == 1, f"detected legacy1 (got {l1['version']})")
    check(len(l1["notes"]) == 1 and len(l1["cards"]) == 1, "1 note / 1 card")

    print("\nlarge.apkg")
    lg = read_apkg(os.path.join(FIX, "large.apkg"))
    check(lg["version"] == 2, "detected legacy2")
    check(len(lg["notes"]) == 4000, f"4000 notes (got {len(lg['notes'])})")
    check(len(lg["cards"]) == 4000, f"4000 cards (got {len(lg['cards'])})")

    print("\nv3stub.apkg")
    v3 = read_apkg(os.path.join(FIX, "v3stub.apkg"))
    check(v3["version"] == 3, f"detected v3/latest (got {v3['version']}) -> Swift importer rejects with guidance")

    print(f"\n{'PASS' if fails == 0 else 'FAIL'}: {fails} failed check(s)")
    return 1 if fails else 0

if __name__ == "__main__":
    sys.exit(main())
