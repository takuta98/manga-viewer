import Foundation

enum SpreadIndex {
    static func pageIndices(
        spreadIndex: Int,
        pageCount: Int,
        coverAlone: Bool,
        layout: PageLayoutMode
    ) -> (Int?, Int?) {
        guard pageCount > 0 else { return (nil, nil) }
        if layout != .spread {
            let i = min(max(spreadIndex, 0), pageCount - 1)
            return (i, nil)
        }
        if coverAlone {
            if spreadIndex == 0 { return (0, nil) }
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

    static func totalSpreads(pageCount: Int, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        guard pageCount > 0 else { return 0 }
        if layout != .spread { return pageCount }
        if coverAlone {
            let rest = max(pageCount - 1, 0)
            return 1 + (rest + 1) / 2
        }
        return (pageCount + 1) / 2
    }

    static func spreadIndex(forPage page: Int, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        if layout != .spread { return page }
        if coverAlone {
            if page <= 0 { return 0 }
            return 1 + (page - 1) / 2
        }
        return page / 2
    }
}
