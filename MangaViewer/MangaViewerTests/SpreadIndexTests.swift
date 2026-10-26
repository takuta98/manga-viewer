import XCTest
@testable import MangaViewer

final class SpreadIndexTests: XCTestCase {
    func testRTLFirstSpreadWithoutCoverAlone() {
        let spread = SpreadIndex.pages(
            for: 0,
            pageCount: 16,
            direction: .rtl,
            coverAlone: false,
            layout: .spread
        )
        XCTAssertEqual(spread.rightIndex, 0)
        XCTAssertEqual(spread.leftIndex, 1)
    }

    func testCoverAlone() {
        let cover = SpreadIndex.pages(
            for: 0,
            pageCount: 16,
            direction: .rtl,
            coverAlone: true,
            layout: .spread
        )
        XCTAssertEqual(cover.rightIndex, 0)
        XCTAssertNil(cover.leftIndex)

        let next = SpreadIndex.pages(
            for: 1,
            pageCount: 16,
            direction: .rtl,
            coverAlone: true,
            layout: .spread
        )
        XCTAssertEqual(next.rightIndex, 1)
        XCTAssertEqual(next.leftIndex, 2)
    }

    func testSingleLayout() {
        let spread = SpreadIndex.pages(
            for: 3,
            pageCount: 16,
            direction: .rtl,
            coverAlone: false,
            layout: .single
        )
        XCTAssertEqual(spread.rightIndex, 3)
        XCTAssertNil(spread.leftIndex)
    }
}
