import CoreGraphics
import Foundation

/// iPhone Duo 専用の見開き判定。
/// - レイアウトは「今の bounds」の関数だけで決める
/// - 計測中に自分のサイズを変えてループさせない
/// - 折りたたみ途中の 0 サイズで木を付け替えない
enum DuoLayout {
    static let explain = "縦や狭い画面は1ページ。十分に広いときだけ見開き（Duo）になります。"

    /// 高さ0など、レイアウトに使えないサイズを弾く。
    static func isUsable(_ size: CGSize) -> Bool {
        size.width >= 80 && size.height >= 80
    }

    static func resolve(containerSize: CGSize, preference: PageLayoutMode) -> PageLayoutMode {
        guard preference == .duo else { return .single }
        guard isUsable(containerSize) else { return .single }
        guard containerSize.width > containerSize.height else { return .single }
        let aspect = containerSize.width / containerSize.height
        guard aspect >= 1.25 else { return .single }
        return .duo
    }
}

enum SpreadIndex {
    static func pageIndices(
        spreadIndex: Int,
        pageCount: Int,
        coverAlone: Bool,
        layout: PageLayoutMode,
        pairBreakAfter: Int? = nil
    ) -> (Int?, Int?) {
        guard pageCount > 0 else { return (nil, nil) }
        if layout != .duo {
            let i = min(max(spreadIndex, 0), pageCount - 1)
            return (i, nil)
        }
        let s = slots(pageCount: pageCount, coverAlone: coverAlone, pairBreakAfter: pairBreakAfter)
        let left = spreadIndex * 2
        let right = left + 1
        return (
            left < s.count ? s[left] : nil,
            right < s.count ? s[right] : nil
        )
    }

    /// 見開きを片ページ単位に並べた読む順の列。偶数長、空きは nil。
    /// pairBreakAfter: そのページ番号の直後に空白を1枚挿してペアをずらす。
    static func slots(pageCount: Int, coverAlone: Bool, pairBreakAfter: Int? = nil) -> [Int?] {
        guard pageCount > 0 else { return [] }
        var result: [Int?] = coverAlone ? [nil] : []
        result.reserveCapacity(pageCount + 3)
        for i in 0..<pageCount {
            result.append(i)
            if i == pairBreakAfter { result.append(nil) }
        }
        if result.count % 2 == 1 { result.append(nil) }
        return result
    }

    static func totalSpreads(pageCount: Int, coverAlone: Bool, layout: PageLayoutMode, pairBreakAfter: Int? = nil) -> Int {
        guard pageCount > 0 else { return 0 }
        if layout != .duo { return pageCount }
        return slots(pageCount: pageCount, coverAlone: coverAlone, pairBreakAfter: pairBreakAfter).count / 2
    }

    static func spreadIndex(forPage page: Int, coverAlone: Bool, layout: PageLayoutMode, pairBreakAfter: Int? = nil) -> Int {
        if layout != .duo { return page }
        var position = (coverAlone ? 1 : 0) + page
        if let k = pairBreakAfter, page > k { position += 1 }
        return position / 2
    }
}
