import Foundation

/// Spread helpers for manga page pairing.
/// RTL (Japanese): right pane = odd page (1-indexed), left pane = even.
struct SpreadPages: Equatable {
    let leftAsset: String?
    let rightAsset: String?
    let leftPageNumber: Int?
    let rightPageNumber: Int?
}

enum SpreadIndex {
    static func spreadCount(pageCount: Int) -> Int {
        max(Int(ceil(Double(pageCount) / 2.0)), 1)
    }

    static func pages(
        for spreadIndex: Int,
        pageAssetNames: [String],
        direction: ReadingDirection
    ) -> SpreadPages {
        let pageCount = pageAssetNames.count
        let clamped = max(0, min(spreadIndex, spreadCount(pageCount: pageCount) - 1))

        switch direction {
        case .rtl:
            let rightNum = clamped * 2 + 1
            let leftNum = clamped * 2 + 2
            return SpreadPages(
                leftAsset: leftNum <= pageCount ? pageAssetNames[leftNum - 1] : nil,
                rightAsset: rightNum <= pageCount ? pageAssetNames[rightNum - 1] : nil,
                leftPageNumber: leftNum <= pageCount ? leftNum : nil,
                rightPageNumber: rightNum <= pageCount ? rightNum : nil
            )
        case .ltr:
            let leftNum = clamped * 2 + 1
            let rightNum = clamped * 2 + 2
            return SpreadPages(
                leftAsset: leftNum <= pageCount ? pageAssetNames[leftNum - 1] : nil,
                rightAsset: rightNum <= pageCount ? pageAssetNames[rightNum - 1] : nil,
                leftPageNumber: leftNum <= pageCount ? leftNum : nil,
                rightPageNumber: rightNum <= pageCount ? rightNum : nil
            )
        }
    }

    /// Single page shown in closed / table poses — prefer the "first" page of the spread in reading order.
    static func closedPage(
        for spreadIndex: Int,
        pageAssetNames: [String],
        direction: ReadingDirection
    ) -> (asset: String?, pageNumber: Int?) {
        let spread = pages(for: spreadIndex, pageAssetNames: pageAssetNames, direction: direction)
        switch direction {
        case .rtl:
            if let right = spread.rightAsset {
                return (right, spread.rightPageNumber)
            }
            return (spread.leftAsset, spread.leftPageNumber)
        case .ltr:
            if let left = spread.leftAsset {
                return (left, spread.leftPageNumber)
            }
            return (spread.rightAsset, spread.rightPageNumber)
        }
    }
}
