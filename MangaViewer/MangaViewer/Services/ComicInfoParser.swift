import Foundation

enum ComicInfoParser {
    static func title(from xmlData: Data) -> String? {
        guard let s = String(data: xmlData, encoding: .utf8) else { return nil }
        guard let r = s.range(of: "<Title>") , let e = s.range(of: "</Title>") else { return nil }
        return String(s[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
