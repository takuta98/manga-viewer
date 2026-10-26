import Foundation

/// リモート一覧のクライアント側絞り込み。現在フォルダの一覧だけを対象にする。
enum RemoteEntryFilter {
    /// 空クエリはそのまま返す。フォルダ・ファイルとも名前で一致（大小無視）。
    static func matching(_ entries: [RemoteEntry], query: String) -> [RemoteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
