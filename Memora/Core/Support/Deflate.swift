//
//  Deflate.swift
//  Memora
//
//  Raw DEFLATE (RFC 1951) inflate/deflate using Apple's Compression framework.
//  ZIP entries (method 8) store raw DEFLATE with no zlib/gzip wrapper, which is
//  exactly what COMPRESSION_ZLIB implements on Apple platforms. Using the
//  system framework keeps Memora free of third-party compression dependencies,
//  consistent with the offline / no-dependencies requirement.
//

import Foundation
import Compression

public enum Deflate {

    public enum DeflateError: Error { case failed }

    /// Inflate raw DEFLATE data. `expectedSize` sizes the first buffer; the
    /// routine still works if the real size differs.
    public static func inflate(_ input: Data, expectedSize: Int = 0) throws -> Data {
        guard !input.isEmpty else { return Data() }
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        dst_size: 0,
                                        src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
                                        src_size: 0,
                                        state: nil)
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw DeflateError.failed }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = max(64 * 1024, min(expectedSize, 4 * 1024 * 1024))
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        var output = Data()
        output.reserveCapacity(expectedSize > 0 ? expectedSize : input.count * 3)

        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { throw DeflateError.failed }
            stream.src_ptr = base
            stream.src_size = input.count
            repeat {
                stream.dst_ptr = dst
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(dst, count: produced) }
            } while status == COMPRESSION_STATUS_OK
        }
        guard status == COMPRESSION_STATUS_END else { throw DeflateError.failed }
        return output
    }

    /// Deflate (compress) to raw DEFLATE data suitable for a ZIP method-8 entry.
    public static func deflate(_ input: Data) throws -> Data {
        guard !input.isEmpty else { return Data() }
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        dst_size: 0,
                                        src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
                                        src_size: 0,
                                        state: nil)
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw DeflateError.failed }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        var output = Data()
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { throw DeflateError.failed }
            stream.src_ptr = base
            stream.src_size = input.count
            repeat {
                stream.dst_ptr = dst
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(dst, count: produced) }
            } while status == COMPRESSION_STATUS_OK
        }
        guard status == COMPRESSION_STATUS_END else { throw DeflateError.failed }
        return output
    }
}
