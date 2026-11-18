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

    public static func inflate(_ input: Data, expectedSize: Int = 0) throws -> Data {
        try process(input, operation: COMPRESSION_STREAM_DECODE,
                    reserve: expectedSize > 0 ? expectedSize : input.count * 3)
    }

    public static func deflate(_ input: Data) throws -> Data {
        try process(input, operation: COMPRESSION_STREAM_ENCODE, reserve: input.count / 2 + 64)
    }

    private static func process(_ input: Data, operation: compression_stream_operation, reserve: Int) throws -> Data {
        guard !input.isEmpty else { return Data() }

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }

        var status = compression_stream_init(streamPtr, operation, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw DeflateError.failed }
        defer { compression_stream_destroy(streamPtr) }

        let bufferSize = 128 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        var output = Data()
        output.reserveCapacity(max(reserve, bufferSize))

        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { throw DeflateError.failed }
            streamPtr.pointee.src_ptr = base
            streamPtr.pointee.src_size = input.count
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            repeat {
                streamPtr.pointee.dst_ptr = dst
                streamPtr.pointee.dst_size = bufferSize
                status = compression_stream_process(streamPtr, flags)
                let produced = bufferSize - streamPtr.pointee.dst_size
                if produced > 0 { output.append(dst, count: produced) }
            } while status == COMPRESSION_STATUS_OK
        }
        guard status == COMPRESSION_STATUS_END else { throw DeflateError.failed }
        return output
    }
}
