import Foundation

enum UserFacingText {
    private static let junk: [NSRegularExpression] = {
        let patterns = [
            #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"#,
            #"^[0-9a-fA-F]{32}[-_]"#,
            #"^tmp[-_]"#,
            #"^temp[-_]"#,
            #"^download[-_]"#,
            #"^wifi-upload[-_]"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    static func title(fromFileName raw: String) -> String {
        var s = (raw as NSString).deletingPathExtension
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return AppCopy.untitled }
        var changed = true
        while changed {
            changed = false
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            for re in junk {
                if let m = re.firstMatch(in: s, options: [], range: range), m.range.location == 0 {
                    s = ns.substring(from: m.range.length)
                    s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
                    changed = true
                    break
                }
            }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        if let slash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: slash)...])
        }
        return s.isEmpty ? AppCopy.untitled : s
    }
}
