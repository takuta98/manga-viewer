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

    func testMatchesCleanedTitle() {
        let entries = [
            RemoteEntry(
                name: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-進撃の巨人.cbz",
                path: "/a.cbz",
                isDirectory: false,
                size: 1
            )
        ]
        let hits = RemoteEntryFilter.matching(entries, query: "進撃")
        XCTAssertEqual(hits.count, 1)
    }

    func testWorksOrderedPutsOffShelfFirst() {
        let entries = [
            RemoteEntry(name: "B.zip", path: "/b", isDirectory: false, size: 1),
            RemoteEntry(name: "A.zip", path: "/a", isDirectory: false, size: 1),
            RemoteEntry(name: "C.zip", path: "/c", isDirectory: false, size: 1),
        ]
        let onShelf: Set<String> = ["/b"]
        let ordered = RemoteEntryFilter.worksOrdered(entries) { onShelf.contains($0.path) }
        XCTAssertEqual(ordered.map(\.path), ["/a", "/c", "/b"])
    }

    func testWorksOrderedSortsByDisplayTitleWithinGroup() {
        let entries = [
            RemoteEntry(name: "C-巻.zip", path: "/c", isDirectory: false, size: 1),
            RemoteEntry(name: "A-巻.zip", path: "/a", isDirectory: false, size: 1),
            RemoteEntry(name: "B-巻.zip", path: "/b", isDirectory: false, size: 1),
        ]
        let ordered = RemoteEntryFilter.worksOrdered(entries) { _ in false }
        XCTAssertEqual(ordered.map(\.path), ["/a", "/b", "/c"])
    }

    func testWorksOrderedKeepsOnShelfTitleOrder() {
        let entries = [
            RemoteEntry(name: "Z.zip", path: "/z", isDirectory: false, size: 1),
            RemoteEntry(name: "M.zip", path: "/m", isDirectory: false, size: 1),
            RemoteEntry(name: "A.zip", path: "/a", isDirectory: false, size: 1),
        ]
        let onShelf: Set<String> = ["/z", "/m", "/a"]
        let ordered = RemoteEntryFilter.worksOrdered(entries) { onShelf.contains($0.path) }
        XCTAssertEqual(ordered.map(\.path), ["/a", "/m", "/z"])
    }

    func testWorksOrderedUsesCleanedDisplayTitle() {
        let entries = [
            RemoteEntry(
                name: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ナルト.zip",
                path: "/n",
                isDirectory: false,
                size: 1
            ),
            RemoteEntry(
                name: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ワンピース.zip",
                path: "/o",
                isDirectory: false,
                size: 1
            ),
        ]
        let ordered = RemoteEntryFilter.worksOrdered(entries) { _ in false }
        // 表示タイトル「ナルト」「ワンピース」で五十音順
        XCTAssertEqual(ordered.map(\.path), ["/n", "/o"])
    }

    func testShelfReadingOrderedByRankThenTitle() {
        let entries = [
            RemoteEntry(name: "C.zip", path: "/c", isDirectory: false, size: 1),
            RemoteEntry(name: "A.zip", path: "/a", isDirectory: false, size: 1),
            RemoteEntry(name: "B.zip", path: "/b", isDirectory: false, size: 1),
            RemoteEntry(name: "D.zip", path: "/d", isDirectory: false, size: 1),
        ]
        let ranks: [String: Int] = ["/c": 2, "/a": 0, "/b": 0, "/d": 1]
        let ordered = RemoteEntryFilter.shelfReadingOrdered(entries) { ranks[$0.path] ?? 99 }
        // 続き(A,B) → 未読(D) → 読了(C)
        XCTAssertEqual(ordered.map(\.path), ["/a", "/b", "/d", "/c"])
    }

    func testShelfReadingOrderedSortsTitlesWithinSameRank() {
        let entries = [
            RemoteEntry(name: "Z.zip", path: "/z", isDirectory: false, size: 1),
            RemoteEntry(name: "M.zip", path: "/m", isDirectory: false, size: 1),
            RemoteEntry(name: "A.zip", path: "/a", isDirectory: false, size: 1),
        ]
        let ordered = RemoteEntryFilter.shelfReadingOrdered(entries) { _ in 0 }
        XCTAssertEqual(ordered.map(\.path), ["/a", "/m", "/z"])
    }

    func testShelfReadingOrderedSortsByPercentThenTitleWithinRank() {
        let entries = [
            RemoteEntry(name: "A.zip", path: "/a", isDirectory: false, size: 1),
            RemoteEntry(name: "B.zip", path: "/b", isDirectory: false, size: 1),
            RemoteEntry(name: "C.zip", path: "/c", isDirectory: false, size: 1),
        ]
        let pct: [String: Int] = ["/a": 20, "/b": 80, "/c": 80]
        let ordered = RemoteEntryFilter.shelfReadingOrdered(
            entries,
            rank: { _ in 0 },
            percent: { pct[$0.path] ?? 0 }
        )
        // 進み％降順、同％はタイトル順 → B(80), C(80), A(20)
        XCTAssertEqual(ordered.map(\.path), ["/b", "/c", "/a"])
    }

    func testShelfReadingOrderedSortsByMarksThenTitleWithinSamePercent() {
        let entries = [
            RemoteEntry(name: "A.zip", path: "/a", isDirectory: false, size: 1),
            RemoteEntry(name: "B.zip", path: "/b", isDirectory: false, size: 1),
            RemoteEntry(name: "C.zip", path: "/c", isDirectory: false, size: 1),
        ]
        let marks: [String: Int] = ["/a": 1, "/b": 3, "/c": 3]
        let ordered = RemoteEntryFilter.shelfReadingOrdered(
            entries,
            rank: { _ in 0 },
            percent: { _ in 50 },
            marks: { marks[$0.path] ?? 0 }
        )
        // しおり件数降順、同件数はタイトル順 → B(3), C(3), A(1)
        XCTAssertEqual(ordered.map(\.path), ["/b", "/c", "/a"])
    }
}
