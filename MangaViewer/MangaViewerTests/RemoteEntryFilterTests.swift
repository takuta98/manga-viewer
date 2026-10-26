import XCTest
@testable import MangaViewer

final class RemoteEntryFilterTests: XCTestCase {
    private let sample: [RemoteEntry] = [
        RemoteEntry(name: "ワンピース", path: "/onepiece", isDirectory: true, size: nil),
        RemoteEntry(name: "ワンピース01.zip", path: "/onepiece01.zip", isDirectory: false, size: 10),
        RemoteEntry(name: "ナルト", path: "/naruto", isDirectory: true, size: nil),
        RemoteEntry(name: "readme.txt", path: "/readme.txt", isDirectory: false, size: 1),
    ]

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(RemoteEntryFilter.matching(sample, query: "").count, 4)
        XCTAssertEqual(RemoteEntryFilter.matching(sample, query: "   ").count, 4)
    }

    func testMatchesFoldersAndFiles() {
        let hits = RemoteEntryFilter.matching(sample, query: "ワンピ")
        XCTAssertEqual(hits.map(\.name), ["ワンピース", "ワンピース01.zip"])
    }

    func testCaseInsensitive() {
        let hits = RemoteEntryFilter.matching(sample, query: "README")
        XCTAssertEqual(hits.map(\.name), ["readme.txt"])
    }

    func testNoMatch() {
        XCTAssertTrue(RemoteEntryFilter.matching(sample, query: "進撃").isEmpty)
    }
}
