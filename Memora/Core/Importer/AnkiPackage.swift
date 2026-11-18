//
//  AnkiPackage.swift
//  Memora
//
//  Opens an .apkg archive, determines its format version, and exposes the
//  collection database and media map.
//
//  Version detection follows Anki's own logic (rslib .../package/meta.rs):
//    • If a `meta` file is present, it is a protobuf `PackageMetadata` whose
//      field 1 is the version (1 = Legacy1, 2 = Legacy2, 3 = Latest/v3).
//    • Otherwise the package is legacy: Legacy2 if `collection.anki21` exists,
//      else Legacy1 (`collection.anki2`).
//
//  Memora fully supports Legacy1 and Legacy2 (plain SQLite schema 11, JSON
//  media map, uncompressed entries). The v3 "Latest" format (zstd-compressed
//  `collection.anki21b`, schema 18, protobuf media index) is detected and
//  reported with actionable guidance rather than failing silently — see
//  docs/LIMITATIONS.md.
//

import Foundation

enum AnkiPackageVersion: Int {
    case legacy1 = 1
    case legacy2 = 2
    case latest = 3

    var collectionFilename: String {
        switch self {
        case .legacy1: return "collection.anki2"
        case .legacy2: return "collection.anki21"
        case .latest: return "collection.anki21b"
        }
    }

    var isLegacy: Bool { self == .legacy1 || self == .legacy2 }
}

final class AnkiPackage {
    let zip: ZipReader
    let version: AnkiPackageVersion

    init(url: URL) throws {
        self.zip = try ZipReader(url: url)
        self.version = try AnkiPackage.detectVersion(in: zip)
    }

    static func detectVersion(in zip: ZipReader) throws -> AnkiPackageVersion {
        if let meta = try? zip.data(forName: "meta") {
            let v = Self.parseMetaVersion(meta)
            guard let version = AnkiPackageVersion(rawValue: v) else {
                throw MemoraError.unsupported(
                    "Este paquete usa un formato de Anki más reciente del que Memora reconoce (versión \(v)).",
                    recovery: "Exporta de nuevo desde Anki marcando «Admitir versiones anteriores de Anki».")
            }
            return version
        }
        if zip.contains("collection.anki21") { return .legacy2 }
        if zip.contains("collection.anki2") { return .legacy1 }
        throw MemoraError.corrupt("El archivo no parece un paquete de Anki (no se encontró la colección).")
    }

    /// Parse protobuf `PackageMetadata { Version version = 1; }`. We only need
    /// field 1 (varint). Returns 0 if not found.
    static func parseMetaVersion(_ data: Data) -> Int {
        var i = 0
        let bytes = [UInt8](data)
        while i < bytes.count {
            let tag = bytes[i]; i += 1
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            if fieldNumber == 1 && wireType == 0 {
                let (value, _) = readVarint(bytes, i)
                return Int(value)
            }
            // Skip other fields.
            switch wireType {
            case 0: (_, i) = readVarint(bytes, i)
            case 2:
                let (len, next) = readVarint(bytes, i)
                i = next + Int(len)
            case 5: i += 4
            case 1: i += 8
            default: return 0
            }
        }
        return 0
    }

    private static func readVarint(_ bytes: [UInt8], _ start: Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < bytes.count {
            let b = bytes[i]; i += 1
            result |= UInt64(b & 0x7F) << shift
            if (b & 0x80) == 0 { break }
            shift += 7
            if shift > 63 { break }
        }
        return (result, i)
    }

    /// Guard against importing a v3 package we can't read yet.
    func ensureSupported() throws {
        if version == .latest {
            throw MemoraError.unsupported(
                "Este paquete usa el formato nuevo de Anki (v3, comprimido con zstd).",
                recovery: "En Anki: Archivo → Exportar → «Paquete de Anki (.apkg)» y marca «Admitir versiones anteriores de Anki». Luego impórtalo de nuevo.")
        }
    }

    /// Extract the collection SQLite database to a temporary file and return
    /// its URL. Caller is responsible for deleting the temp directory.
    func extractCollection(to directory: URL) throws -> URL {
        try ensureSupported()
        let name = version.collectionFilename
        guard zip.contains(name) else {
            throw MemoraError.corrupt("El paquete no contiene '\(name)'.")
        }
        let bytes = try zip.data(forName: name)
        let dbURL = directory.appendingPathComponent("collection.sqlite")
        try bytes.write(to: dbURL, options: .atomic)
        return dbURL
    }

    /// Legacy media map: JSON object mapping the numeric archive entry name to
    /// the real filename, e.g. {"0":"image.png","1":"audio.mp3"}.
    func legacyMediaMap() -> [String: String] {
        guard let data = try? zip.data(forName: "media") else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            // Some exports store values as any; coerce.
            if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var map: [String: String] = [:]
                for (k, v) in any { if let s = v as? String { map[k] = s } }
                return map
            }
            return [:]
        }
        return obj
    }
}
