import XCTest
@testable import MangaViewer

final class UserFacingTextTests: XCTestCase {
    func testStripsUUIDPrefixFromTitle() {
        let contaminated = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ワンピース"
        XCTAssertEqual(UserFacingText.clean(contaminated), "ワンピース")
    }

    func testTitleFromFileNameIgnoresExtension() {
        XCTAssertEqual(UserFacingText.title(fromFileName: "comic.cbz"), "comic")
    }

    func testTitleFromContaminatedURL() {
        let url = URL(fileURLWithPath: "/tmp/A1B2C3D4-E5F6-7890-ABCD-EF1234567890-book.cbz")
        XCTAssertEqual(UserFacingText.title(from: url), "book")
    }

    func testImportStagingKeepsCleanFileName() throws {
        let url = try ImportStaging.fileURL(named: "名作.cbz")
        XCTAssertEqual(url.lastPathComponent, "名作.cbz")
        XCTAssertFalse(url.lastPathComponent.contains("A1B2"))
        ImportStaging.removeSession(containing: url)
    }

    func testEmptyBecomesUntitled() {
        XCTAssertEqual(UserFacingText.clean("   "), "無題")
    }
}
