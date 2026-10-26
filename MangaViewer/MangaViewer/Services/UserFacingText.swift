import Foundation

/// ユーザーに見せる文字列の単一入口。
/// 実装都合（UUID・一時パス・デバッグ接頭辞）を UI / 永続タイトルに絶対に混ぜない。
enum UserFacingText {
    /// UUID（ハイフンあり/なし）の直後に区切りがある接頭辞。
    private static let junkPrefixPatterns: [NSRegularExpression] = {
        let raw = [
            #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"#,
            #"^[0-9a-fA-F]{32}[-_]"#,
            #"^tmp[-_]"#,
            #"^temp[-_]"#,
            #"^download[-_]"#,
            #"^wifi-upload[-_]"#
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// ファイル名 / パス末尾から表示用タイトルを作る。拡張子は落とす。
    static func title(fromFileName name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return clean(base)
    }

    /// URL から表示用タイトル（パスの実装都合を除去）。
    static func title(from url: URL) -> String {
        title(fromFileName: url.lastPathComponent)
    }

    /// 既存の汚染タイトルを修復する。
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "無題" }

        var changed = true
        while changed {
            changed = false
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            for pattern in junkPrefixPatterns {
                if let match = pattern.firstMatch(in: s, options: [], range: range), match.range.location == 0 {
                    s = ns.substring(from: match.range.length)
                    changed = true
                    break
                }
            }
        }

        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        if s.isEmpty { return "無題" }
        // パス区切りが混入していたら末尾だけ
        if s.contains("/") {
            s = (s as NSString).lastPathComponent
        }
        return s.isEmpty ? "無題" : s
    }

    static func isContaminated(_ raw: String) -> Bool {
        clean(raw) != raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
