import XCTest
@testable import DuoSpread

final class SpreadIndexTests: XCTestCase {
    private let pages = (1...16).map { String(format: "night-station-%03d", $0) }

    func testSpreadCount() {
        XCTAssertEqual(SpreadIndex.spreadCount(pageCount: 16), 8)
        XCTAssertEqual(SpreadIndex.spreadCount(pageCount: 15), 8)
        XCTAssertEqual(SpreadIndex.spreadCount(pageCount: 1), 1)
    }

    func testRTLFirstSpread() {
        let spread = SpreadIndex.pages(for: 0, pageAssetNames: pages, direction: .rtl)
        XCTAssertEqual(spread.rightPageNumber, 1)
        XCTAssertEqual(spread.leftPageNumber, 2)
        XCTAssertEqual(spread.rightAsset, "night-station-001")
        XCTAssertEqual(spread.leftAsset, "night-station-002")
    }

    func testRTLSecondSpread() {
        let spread = SpreadIndex.pages(for: 1, pageAssetNames: pages, direction: .rtl)
        XCTAssertEqual(spread.rightPageNumber, 3)
        XCTAssertEqual(spread.leftPageNumber, 4)
    }

    func testRTLOddLastPage() {
        let oddPages = Array(pages.prefix(15))
        let spread = SpreadIndex.pages(for: 7, pageAssetNames: oddPages, direction: .rtl)
        XCTAssertEqual(spread.rightPageNumber, 15)
        XCTAssertNil(spread.leftAsset)
        XCTAssertNil(spread.leftPageNumber)
    }

    func testClosedPrefersRightInRTL() {
        let page = SpreadIndex.closedPage(for: 0, pageAssetNames: pages, direction: .rtl)
        XCTAssertEqual(page.pageNumber, 1)
        XCTAssertEqual(page.asset, "night-station-001")
    }
}
