import XCTest
@testable import MangaViewer

final class TitleCleanerTests: XCTestCase {
    func testStripsUUIDPrefix() {
        XCTAssertEqual(
            TitleCleaner.clean("A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ワンピース"),
            "ワンピース"
        )
        XCTAssertEqual(TitleCleaner.clean("普通のタイトル"), "普通のタイトル")
        XCTAssertEqual(TitleCleaner.clean(""), "無題")
    }
}
