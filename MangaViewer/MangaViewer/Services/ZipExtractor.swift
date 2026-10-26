import Foundation
import Compression

/// CBZ/ZIP から画像だけ取り出す。Stored と Deflate のみ。
enum ZipExtractor {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic"]

    static func extractImages(from zipURL: URL, into directory: URL) throws -> [String] {
        let data = try Data(contentsOf: zipURL)
        var offset = 0
        var extracted: [(name: String, bytes: Data)] = []

        while offset + 30 <= data.count {
            let signature = readU32(data, offset)
            guard signature == 0x04034b50 else { break }

            let method = Int(readU16(data, offset + 8))
            let compressedSize = Int(readU32(data, offset + 18))
            let uncompressedSize = Int(readU32(data, offset + 22))
            let nameLength = Int(readU16(data, offset + 26))
            let extraLength = Int(readU16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= data.count else { break }

            let rawName = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? ""
            offset = dataEnd

            let fileName = (rawName as NSString).lastPathComponent
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard imageExtensions.contains(ext), !rawName.contains("__MACOSX") else { continue }

            let payload = data.subdata(in: dataStart..<dataEnd)
            let bytes: Data
            switch method {
            case 0:
                bytes = payload
            case 8:
                bytes = try inflate(payload, expectedSize: uncompressedSize)
            default:
                continue
            }
            extracted.append((fileName, bytes))
        }

        extracted.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var names: [String] = []
        for (i, item) in extracted.enumerated() {
            let ext = (item.name as NSString).pathExtension.lowercased()
            let outName = String(format: "%04d.%@", i + 1, ext)
            try item.bytes.write(to: directory.appendingPathComponent(outName), options: .atomic)
            names.append(outName)
        }
        return names
    }

    private static func readU16(_ data: Data, _ o: Int) -> UInt16 {
        UInt16(data[o]) | (UInt16(data[o + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ o: Int) -> UInt32 {
        UInt32(readU16(data, o)) | (UInt32(readU16(data, o + 2)) << 16)
    }

    private static func inflate(_ source: Data, expectedSize: Int) throws -> Data {
        var destination = Data(count: max(expectedSize, source.count * 4))
        let written: Int = destination.withUnsafeMutableBytes { destBuf in
            source.withUnsafeBytes { srcBuf in
                guard let d = destBuf.bindMemory(to: UInt8.self).baseAddress,
                      let s = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return compression_decode_buffer(d, destBuf.count, s, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else {
            throw NSError(
                domain: "ZipExtractor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ZIP の展開に失敗しました"]
            )
        }
        return destination.prefix(written)
    }
}
