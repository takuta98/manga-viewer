import Foundation

struct SpreadPages: Equatable {
    let leftIndex: Int?
    let rightIndex: Int?
}

enum SpreadIndex {
    /// When coverAlone, page 0 stands alone; subsequent pages pair as 1|2, 3|4...
    static func spreadCount(pageCount: Int, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        guard pageCount > 0 else { return 1 }
        if layout == .single || layout == .webtoon { return pageCount }
        if coverAlone {
            if pageCount == 1 { return 1 }
            return 1 + Int(ceil(Double(pageCount - 1) / 2.0))
        }
        return Int(ceil(Double(pageCount) / 2.0))
    }

    static func pages(
        for spreadIndex: Int,
        pageCount: Int,
        direction: ReadingDirection,
        coverAlone: Bool,
        layout: PageLayoutMode
    ) -> SpreadPages {
        guard pageCount > 0 else { return SpreadPages(leftIndex: nil, rightIndex: nil) }
        let maxSpread = spreadCount(pageCount: pageCount, coverAlone: coverAlone, layout: layout) - 1
        let clamped = max(0, min(spreadIndex, maxSpread))

        if layout == .single || layout == .webtoon {
            let idx = clamped
            switch direction {
            case .rtl: return SpreadPages(leftIndex: nil, rightIndex: idx)
            case .ltr: return SpreadPages(leftIndex: idx, rightIndex: nil)
            }
        }

        let first: Int
        let second: Int?
        if coverAlone {
            if clamped == 0 {
                first = 0
                second = nil
            } else {
                first = (clamped - 1) * 2 + 1
                let s = first + 1
                second = s < pageCount ? s : nil
            }
        } else {
            first = clamped * 2
            let s = first + 1
            second = s < pageCount ? s : nil
        }

        switch direction {
        case .rtl:
            // Read first on the right.
            return SpreadPages(leftIndex: second, rightIndex: first)
        case .ltr:
            return SpreadPages(leftIndex: first, rightIndex: second)
        }
    }

    static func closedPageIndex(
        for spreadIndex: Int,
        pageCount: Int,
        direction: ReadingDirection,
        coverAlone: Bool,
        layout: PageLayoutMode
    ) -> Int? {
        let spread = pages(
            for: spreadIndex,
            pageCount: pageCount,
            direction: direction,
            coverAlone: coverAlone,
            layout: layout
        )
        switch direction {
        case .rtl: return spread.rightIndex ?? spread.leftIndex
        case .ltr: return spread.leftIndex ?? spread.rightIndex
        }
    }
}
