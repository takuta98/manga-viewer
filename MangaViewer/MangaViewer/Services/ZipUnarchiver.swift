import Foundation
import zlib

/// Minimal ZIP reader for CBZ/ZIP (store + deflate).
enum ZipUnarchiver {
    enum ZipError: Error {
        case invalidArchive
        case unsupportedCompression
        case inflateFailed
    }

    static func unzip(archiveURL: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let data = try Data(contentsOf: archiveURL)
        var offset = 0
        while offset + 30 <= data.count {
            let sig = readUInt32(data, offset)
            if sig != 0x04034b50 { break }
            let method = Int(readUInt16(data, offset + 8))
            let flags = Int(readUInt16(data, offset + 6))
            let compSizeField = Int(readUInt32(data, offset + 18))
            let uncompSize = Int(readUInt32(data, offset + 22))
            let nameLen = Int(readUInt16(data, offset + 26))
            let extraLen = Int(readUInt16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen <= data.count else { throw ZipError.invalidArchive }
            let fileName = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? "file"
            let dataStart = nameEnd + extraLen
            let hasDataDescriptor = (flags & 0x08) != 0
            let compSize = compSizeField
            if hasDataDescriptor && compSize == 0 {
                throw ZipError.unsupportedCompression
            }
            let dataEnd = dataStart + compSize
            guard dataEnd <= data.count else { throw ZipError.invalidArchive }
            let payload = data.subdata(in: dataStart..<dataEnd)
            offset = dataEnd

            if fileName.hasSuffix("/") { continue }
            if fileName.hasPrefix("__MACOSX") { continue }

            let outURL = destination.appendingPathComponent(fileName)
            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            switch method {
            case 0:
                try payload.write(to: outURL)
            case 8:
                try inflateRaw(payload).write(to: outURL)
                _ = uncompSize
            default:
                throw ZipError.unsupportedCompression
            }
        }
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func inflateRaw(_ input: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipError.inflateFailed
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunk = 65_536
        var outBuffer = [UInt8](repeating: 0, count: chunk)
        var status: Int32 = Z_OK

        input.withUnsafeBytes { srcRaw in
            guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: srcBase)
            stream.avail_in = uInt(input.count)
            while status != Z_STREAM_END {
                outBuffer.withUnsafeMutableBytes { outRaw in
                    stream.next_out = outRaw.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(chunk)
                    status = inflate(&stream, Z_NO_FLUSH)
                    let produced = chunk - Int(stream.avail_out)
                    if produced > 0, let base = outRaw.bindMemory(to: UInt8.self).baseAddress {
                        output.append(base, count: produced)
                    }
                }
                if status == Z_BUF_ERROR { break }
                if status != Z_OK && status != Z_STREAM_END { break }
            }
        }
        guard status == Z_STREAM_END || !output.isEmpty else { throw ZipError.inflateFailed }
        return output
    }
}
