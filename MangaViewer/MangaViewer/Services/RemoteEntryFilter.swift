import Foundation

/// リモート一覧のクライアント側絞り込み。現在フォルダの一覧だけを対象にする。
enum RemoteEntryFilter {
    /// 空クエリはそのまま返す。ファイル名と表示用タイトルの両方で一致（大小無視）。
    static func matching(_ entries: [RemoteEntry], query: String) -> [RemoteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || UserFacingText.title(fromFileName: $0.name).localizedCaseInsensitiveContains(q)
        }
    }

    /// 未入手を先に、表示タイトルで並べる（作品選びUI用）。
    static func worksOrdered(
        _ entries: [RemoteEntry],
        onShelf: (RemoteEntry) -> Bool
    ) -> [RemoteEntry] {
        entries.sorted { a, b in
            let aOn = onShelf(a)
            let bOn = onShelf(b)
            if aOn != bOn { return !aOn && bOn }
            let at = UserFacingText.title(fromFileName: a.name)
            let bt = UserFacingText.title(fromFileName: b.name)
            return at.localizedStandardCompare(bt) == .orderedAscending
        }
    }

    /// 本棚側：続き → 未読 → 読了。
    /// 同ランク内は進み％降順 → しおり件数降順 → 表示タイトル順（TransferStatus / readyChip と同じ）。
    /// rank: 0=続き, 1=未読, 2=読了（呼び出し側が Progress から算出）
    static func shelfReadingOrdered(
        _ entries: [RemoteEntry],
        rank: (RemoteEntry) -> Int,
        percent: (RemoteEntry) -> Int = { _ in 0 },
        marks: (RemoteEntry) -> Int = { _ in 0 }
    ) -> [RemoteEntry] {
        entries.sorted { a, b in
            let ra = rank(a)
            let rb = rank(b)
            if ra != rb { return ra < rb }
            let pa = percent(a)
            let pb = percent(b)
            if pa != pb { return pa > pb }
            let ma = marks(a)
            let mb = marks(b)
            if ma != mb { return ma > mb }
            let at = UserFacingText.title(fromFileName: a.name)
            let bt = UserFacingText.title(fromFileName: b.name)
            return at.localizedStandardCompare(bt) == .orderedAscending
        }
    }
}
