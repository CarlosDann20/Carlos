//
//  ZipWriter.swift
//  Memora
//
//  Minimal ZIP writer (STORE + DEFLATE) used to produce .apkg exports and
//  backups. Entries are buffered and the archive is written in one pass:
//  local headers + data, then the central directory, then the EOCD.
//
//  Standard ZIP (not ZIP64); for Memora's exports this comfortably covers
//  typical collections. Very large exports (>65,535 entries) are noted as a
//  limitation.
//

import Foundation

public final class ZipWriter {
    private struct Entry {
        let name: String
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let method: UInt16
        let offset: UInt32
        let data: Data
    }

    private var entries: [Entry] = []
    private var buffer = Data()

    public init() {}

    /// Add an entry. If `compress` is true (default) the data is DEFLATE-d when
    /// that makes it smaller; otherwise it is stored.
    public func add(_ name: String, data: Data, compress: Bool = true) {
        let crc = CRC32.checksum(data)
        var method: UInt16 = 0
        var payload = data
        if compress, !data.isEmpty, let deflated = try? Deflate.deflate(data), deflated.count < data.count {
            method = 8
            payload = deflated
        }
        let offset = UInt32(buffer.count)
        appendLocalHeader(name: name, crc: crc, compSize: UInt32(payload.count),
                          uncompSize: UInt32(data.count), method: method)
        buffer.append(payload)
        entries.append(Entry(name: name, crc: crc, compressedSize: UInt32(payload.count),
                             uncompressedSize: UInt32(data.count), method: method,
                             offset: offset, data: payload))
    }

    public func finish() -> Data {
        let cdStart = UInt32(buffer.count)
        var cd = Data()
        for e in entries {
            let nameBytes = Array(e.name.utf8)
            appendU32(&cd, 0x02014b50)
            appendU16(&cd, 20)                // version made by
            appendU16(&cd, 20)                // version needed
            appendU16(&cd, 0)                 // flags
            appendU16(&cd, e.method)
            appendU16(&cd, 0)                 // mod time
            appendU16(&cd, 0)                 // mod date
            appendU32(&cd, e.crc)
            appendU32(&cd, e.compressedSize)
            appendU32(&cd, e.uncompressedSize)
            appendU16(&cd, UInt16(nameBytes.count))
            appendU16(&cd, 0)                 // extra len
            appendU16(&cd, 0)                 // comment len
            appendU16(&cd, 0)                 // disk start
            appendU16(&cd, 0)                 // internal attrs
            appendU32(&cd, 0)                 // external attrs
            appendU32(&cd, e.offset)
            cd.append(contentsOf: nameBytes)
        }
        let cdSize = UInt32(cd.count)
        buffer.append(cd)

        // EOCD
        var eocd = Data()
        appendU32(&eocd, 0x06054b50)
        appendU16(&eocd, 0)                   // disk number
        appendU16(&eocd, 0)                   // disk with CD
        appendU16(&eocd, UInt16(entries.count))
        appendU16(&eocd, UInt16(entries.count))
        appendU32(&eocd, cdSize)
        appendU32(&eocd, cdStart)
        appendU16(&eocd, 0)                   // comment len
        buffer.append(eocd)
        return buffer
    }

    // MARK: - Header writers

    private func appendLocalHeader(name: String, crc: UInt32, compSize: UInt32, uncompSize: UInt32, method: UInt16) {
        let nameBytes = Array(name.utf8)
        appendU32(&buffer, 0x04034b50)
        appendU16(&buffer, 20)
        appendU16(&buffer, 0)
        appendU16(&buffer, method)
        appendU16(&buffer, 0)
        appendU16(&buffer, 0)
        appendU32(&buffer, crc)
        appendU32(&buffer, compSize)
        appendU32(&buffer, uncompSize)
        appendU16(&buffer, UInt16(nameBytes.count))
        appendU16(&buffer, 0)
        buffer.append(contentsOf: nameBytes)
    }

    private func appendU16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF))
    }
    private func appendU32(_ data: inout Data, _ value: UInt32) {
        for i in 0..<4 { data.append(UInt8((value >> (8 * UInt32(i))) & 0xFF)) }
    }
}
