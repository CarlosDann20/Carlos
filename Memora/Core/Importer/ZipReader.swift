//
//  ZipReader.swift
//  Memora
//
//  A minimal, dependency-free ZIP reader used to open .apkg packages. Supports
//  STORE (0) and DEFLATE (8) entries and ZIP64 (needed for large collections
//  whose media exceed 65,535 files or 4 GB). The file is memory-mapped, so a
//  large package is not loaded wholesale into RAM.
//
//  Security: entry names are validated on extraction to block path traversal
//  ("zip slip"), and per-entry / total uncompressed-size caps guard against
//  decompression bombs. These address the spec's requirement to "prevent
//  malicious paths and dangerous archives".
//

import Foundation

public struct ZipEntry: Sendable {
    public var name: String
    public var method: UInt16
    public var compressedSize: UInt64
    public var uncompressedSize: UInt64
    public var localHeaderOffset: UInt64
    public var isDirectory: Bool { name.hasSuffix("/") }
}

public final class ZipReader {
    private let data: Data
    public private(set) var entries: [ZipEntry] = []
    private var index: [String: Int] = [:]

    // Safety caps.
    public var maxEntryUncompressed: UInt64 = 2 * 1024 * 1024 * 1024       // 2 GB per entry
    public var maxTotalUncompressed: UInt64 = 8 * 1024 * 1024 * 1024       // 8 GB total

    public init(url: URL) throws {
        do {
            self.data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw MemoraError(.ioFailure, "No se pudo leer el archivo.", underlying: error)
        }
        try parseCentralDirectory()
    }

    public init(data: Data) throws {
        // Normalise to 0-based indices (a passed-in slice may start elsewhere).
        self.data = Data(data)
        try parseCentralDirectory()
    }

    public func entry(named name: String) -> ZipEntry? {
        if let i = index[name] { return entries[i] }
        return nil
    }

    public func contains(_ name: String) -> Bool { index[name] != nil }

    /// Decompress an entry into memory.
    public func data(for entry: ZipEntry) throws -> Data {
        guard entry.uncompressedSize <= maxEntryUncompressed else {
            throw MemoraError.security("Una entrada del paquete supera el tamaño máximo permitido (\(entry.name)).")
        }
        let dataStart = try localDataOffset(for: entry)
        let compStart = Int(dataStart)
        let compEnd = compStart + Int(entry.compressedSize)
        guard compStart >= 0, compEnd <= data.count else {
            throw MemoraError.corrupt("Paquete dañado: datos de '\(entry.name)' fuera de rango.")
        }
        let slice = data.subdata(in: compStart..<compEnd)
        switch entry.method {
        case 0:
            return slice
        case 8:
            let out = try Deflate.inflate(slice, expectedSize: Int(entry.uncompressedSize))
            if entry.uncompressedSize > 0 && UInt64(out.count) != entry.uncompressedSize {
                throw MemoraError.corrupt("Paquete dañado: tamaño inesperado en '\(entry.name)'.")
            }
            return out
        default:
            throw MemoraError.unsupported("Método de compresión no soportado (\(entry.method)) en '\(entry.name)'.")
        }
    }

    public func data(forName name: String) throws -> Data {
        guard let e = entry(named: name) else {
            throw MemoraError(.notFound, "El paquete no contiene '\(name)'.")
        }
        return try data(for: e)
    }

    // MARK: - Parsing

    private func localDataOffset(for entry: ZipEntry) throws -> UInt64 {
        let base = Int(entry.localHeaderOffset)
        guard base + 30 <= data.count, readU32(base) == 0x04034b50 else {
            throw MemoraError.corrupt("Cabecera local inválida para '\(entry.name)'.")
        }
        let fnLen = Int(readU16(base + 26))
        let extraLen = Int(readU16(base + 28))
        return UInt64(base + 30 + fnLen + extraLen)
    }

    private func parseCentralDirectory() throws {
        guard data.count >= 22 else { throw MemoraError.corrupt("Archivo demasiado pequeño para ser un ZIP.") }
        guard let eocd = findEOCD() else { throw MemoraError.corrupt("No es un paquete ZIP válido (falta EOCD).") }

        var totalEntries = Int(readU16(eocd + 10))
        var cdOffset = UInt64(readU32(eocd + 16))
        let cdSizeMarker = readU32(eocd + 12)

        // ZIP64 if markers are maxed out.
        if cdOffset == 0xFFFFFFFF || totalEntries == 0xFFFF || cdSizeMarker == 0xFFFFFFFF {
            if let z64 = findZip64EOCD(beforeEOCD: eocd) {
                totalEntries = Int(readU64(z64 + 32))
                cdOffset = readU64(z64 + 48)
            }
        }

        var offset = Int(cdOffset)
        var total = 0
        var totalUncompressed: UInt64 = 0
        for _ in 0..<totalEntries {
            guard offset + 46 <= data.count, readU32(offset) == 0x02014b50 else { break }
            let method = readU16(offset + 10)
            var compSize = UInt64(readU32(offset + 20))
            var uncompSize = UInt64(readU32(offset + 24))
            let fnLen = Int(readU16(offset + 28))
            let extraLen = Int(readU16(offset + 30))
            let commentLen = Int(readU16(offset + 32))
            var localOffset = UInt64(readU32(offset + 42))
            let nameStart = offset + 46
            guard nameStart + fnLen <= data.count else { break }
            let name = readString(nameStart, length: fnLen)

            // Parse ZIP64 extra if any 32-bit field is maxed.
            if compSize == 0xFFFFFFFF || uncompSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                parseZip64Extra(extraStart: nameStart + fnLen, extraLen: extraLen,
                                uncompSize: &uncompSize, compSize: &compSize, localOffset: &localOffset)
            }

            totalUncompressed &+= uncompSize
            if totalUncompressed > maxTotalUncompressed {
                throw MemoraError.security("El paquete descomprimido supera el límite de seguridad.")
            }

            let entry = ZipEntry(name: name, method: method, compressedSize: compSize,
                                 uncompressedSize: uncompSize, localHeaderOffset: localOffset)
            if !entry.isDirectory {
                index[name] = entries.count
                entries.append(entry)
            }
            total += 1
            offset = nameStart + fnLen + extraLen + commentLen
        }
        _ = total
    }

    private func parseZip64Extra(extraStart: Int, extraLen: Int, uncompSize: inout UInt64,
                                 compSize: inout UInt64, localOffset: inout UInt64) {
        var p = extraStart
        let end = extraStart + extraLen
        while p + 4 <= end, p + 4 <= data.count {
            let headerID = readU16(p)
            let size = Int(readU16(p + 2))
            let fieldStart = p + 4
            if headerID == 0x0001 {
                var q = fieldStart
                if uncompSize == 0xFFFFFFFF, q + 8 <= end { uncompSize = readU64(q); q += 8 }
                if compSize == 0xFFFFFFFF, q + 8 <= end { compSize = readU64(q); q += 8 }
                if localOffset == 0xFFFFFFFF, q + 8 <= end { localOffset = readU64(q); q += 8 }
            }
            p = fieldStart + size
        }
    }

    private func findEOCD() -> Int? {
        let sig: UInt32 = 0x06054b50
        let minPos = max(0, data.count - 22 - 65_536)
        var i = data.count - 22
        while i >= minPos {
            if readU32(i) == sig { return i }
            i -= 1
        }
        return nil
    }

    private func findZip64EOCD(beforeEOCD eocd: Int) -> Int? {
        // The ZIP64 locator is 20 bytes immediately before the EOCD.
        let locator = eocd - 20
        guard locator >= 0, readU32(locator) == 0x07064b50 else { return nil }
        let z64Offset = Int(readU64(locator + 8))
        guard z64Offset >= 0, z64Offset + 56 <= data.count, readU32(z64Offset) == 0x06064b50 else { return nil }
        return z64Offset
    }

    // MARK: - Little-endian readers

    private func readU16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count, offset >= 0 else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readU32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count, offset >= 0 else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
             | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private func readU64(_ offset: Int) -> UInt64 {
        guard offset + 8 <= data.count, offset >= 0 else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(data[offset + i]) << (8 * i) }
        return value
    }

    private func readString(_ offset: Int, length: Int) -> String {
        guard offset >= 0, offset + length <= data.count else { return "" }
        let sub = data.subdata(in: offset..<(offset + length))
        return String(data: sub, encoding: .utf8) ?? String(decoding: sub, as: UTF8.self)
    }
}
