import CoreGraphics
import Foundation

/// iPhone Duo / 広い画面向けの見開き判定。
///
/// Apple の指針:
/// - レイアウトは「今の bounds」の関数にする
/// - 計測中の View 自身のサイズを変えてループさせない
/// - 一時的な 0 サイズで木を付け替えない
enum DuoLayout {
    static let explain = "縦や狭い画面は1ページ。十分に広いときだけ見開き（Duo）になります。"

    /// 折りたたみ途中などの不正サイズ（高さ0など）を弾く。
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
        layout: PageLayoutMode
    ) -> (Int?, Int?) {
        guard pageCount > 0 else { return (nil, nil) }
        if layout != .duo {
            let i = min(max(spreadIndex, 0), pageCount - 1)
            return (i, nil)
        }
        if coverAlone {
            // 表紙は見開きの読む順で2枚目（左開きは右側、右開きは左側）に置く。
            if spreadIndex == 0 { return (nil, 0) }
            let start = 1 + (spreadIndex - 1) * 2
            let left = start < pageCount ? start : nil
            let right = start + 1 < pageCount ? start + 1 : nil
            return (left, right)
        }
        let start = spreadIndex * 2
        let left = start < pageCount ? start : nil
        let right = start + 1 < pageCount ? start + 1 : nil
        return (left, right)
    }

    /// 見開きを片ページ単位に並べた読む順の列。偶数長、空きは nil。
    /// slots[2s], slots[2s+1] が見開き s の (1枚目, 2枚目)。
    static func slots(pageCount: Int, coverAlone: Bool) -> [Int?] {
        guard pageCount > 0 else { return [] }
        var result: [Int?] = coverAlone ? [nil] : []
        result.append(contentsOf: (0..<pageCount).map { Optional($0) })
        if result.count % 2 == 1 { result.append(nil) }
        return result
    }

    static func totalSpreads(pageCount: Int, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        guard pageCount > 0 else { return 0 }
        if layout != .duo { return pageCount }
        if coverAlone {
            let rest = max(pageCount - 1, 0)
            return 1 + (rest + 1) / 2
        }
        return (pageCount + 1) / 2
    }

    static func spreadIndex(forPage page: Int, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        if layout != .duo { return page }
        if coverAlone {
            if page <= 0 { return 0 }
            return 1 + (page - 1) / 2
        }
        return page / 2
    }
}
