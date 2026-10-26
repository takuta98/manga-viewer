import Foundation
import Compression

/// 最小の ZIP 展開（Stored / Deflate）。外部パッケージ不使用。
enum ZipUnarchiver {
    static func extractImages(from zipURL: URL, to directory: URL) throws -> [String] {
        let data = try Data(contentsOf: zipURL)
        var offset = 0
        var pages: [(name: String, data: Data)] = []
        while offset + 30 <= data.count {
            let sig = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            if sig != 0x04034b50 { break }
            let method = Int(data[offset+8]) | (Int(data[offset+9]) << 8)
            let compSize = readU32(data, offset + 18)
            let uncompSize = readU32(data, offset + 22)
            let nameLen = Int(readU16(data, offset + 26))
            let extraLen = Int(readU16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen + Int(compSize) <= data.count else { break }
            let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? ""
            let dataStart = nameEnd + extraLen
            let dataEnd = dataStart + Int(compSize)
            let payload = data.subdata(in: dataStart..<dataEnd)
            offset = dataEnd
            let base = (name as NSString).lastPathComponent
            let ext = (base as NSString).pathExtension.lowercased()
            guard MangaImporter.isImage(ext), !name.contains("__MACOSX") else { continue }
            let raw: Data
            if method == 0 {
                raw = payload
            } else if method == 8 {
                raw = try inflate(payload, expected: Int(uncompSize))
            } else {
                continue
            }
            pages.append((base, raw))
        }
        pages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var names: [String] = []
        for (i, page) in pages.enumerated() {
            let ext = (page.name as NSString).pathExtension.lowercased()
            let outName = String(format: "%04d.%@", i + 1, ext)
            try page.data.write(to: directory.appendingPathComponent(outName))
            names.append(outName)
        }
        return names
    }

    private static func readU16(_ data: Data, _ o: Int) -> UInt16 {
        UInt16(data[o]) | (UInt16(data[o+1]) << 8)
    }
    private static func readU32(_ data: Data, _ o: Int) -> UInt32 {
        UInt32(readU16(data, o)) | (UInt32(readU16(data, o+2)) << 16)
    }

    private static func inflate(_ data: Data, expected: Int) throws -> Data {
        var dest = Data(count: max(expected, data.count * 4))
        let result: Int = dest.withUnsafeMutableBytes { destBuf in
            data.withUnsafeBytes { srcBuf in
                guard let d = destBuf.bindMemory(to: UInt8.self).baseAddress,
                      let s = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                var dsize = destBuf.count
                let status = compression_decode_buffer(d, dsize, s, data.count, nil, COMPRESSION_ZLIB)
                return status
            }
        }
        guard result > 0 else {
            throw NSError(domain: "ZipUnarchiver", code: 1, userInfo: [NSLocalizedDescriptionKey: AppCopy.zipExtractFailed])
        }
        return dest.prefix(result)
    }
}
