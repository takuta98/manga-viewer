import XCTest
@testable import MangaViewer

final class UserFacingTextTests: XCTestCase {
    func testStripsUUIDPrefix() {
        XCTAssertEqual(UserFacingText.title(fromFileName: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ワンピース"), "ワンピース")
        XCTAssertEqual(UserFacingText.title(fromFileName: "普通のタイトル"), "普通のタイトル")
        XCTAssertEqual(UserFacingText.title(fromFileName: ""), "無題")
    }
}
