import XCTest
@testable import MangaViewer

final class SpreadIndexTests: XCTestCase {
    func testPortraitUsesSinglePages() {
        XCTAssertEqual(SpreadIndex.totalSpreads(pageCount: 10, coverAlone: true, layout: .single), 10)
    }
}
