import CoreGraphics
import XCTest
@testable import MangaViewer

final class DuoLayoutTests: XCTestCase {
    func testPortraitIsSingle() {
        let layout = DuoLayout.resolve(
            containerSize: CGSize(width: 390, height: 844),
            preference: .duo
        )
        XCTAssertEqual(layout, .single)
    }

    func testWideLandscapeIsDuo() {
        let layout = DuoLayout.resolve(
            containerSize: CGSize(width: 844, height: 390),
            preference: .duo
        )
        XCTAssertEqual(layout, .duo)
    }

    func testPreferenceSingleForcesSingle() {
        let layout = DuoLayout.resolve(
            containerSize: CGSize(width: 844, height: 390),
            preference: .single
        )
        XCTAssertEqual(layout, .single)
    }

    func testCoverAloneSpreadCount() {
        XCTAssertEqual(
            SpreadIndex.totalSpreads(pageCount: 5, coverAlone: true, layout: .duo),
            3
        )
    }
}
