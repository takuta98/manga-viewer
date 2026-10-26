import Foundation

enum TitleCleaner {
    private static let patterns: [NSRegularExpression] = {
        [
            #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"#,
            #"^[0-9a-fA-F]{32}[-_]"#,
            #"^tmp[-_]"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    static func clean(_ raw: String) -> String {
        var s = (raw as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "無題" }
        var changed = true
        while changed {
            changed = false
            let ns = s as NSString
            let full = NSRange(location: 0, length: ns.length)
            for re in patterns {
                if let m = re.firstMatch(in: s, options: [], range: full), m.range.location == 0 {
                    s = ns.substring(from: m.range.length)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
                    changed = true
                    break
                }
            }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        return s.isEmpty ? "無題" : s
    }
}
