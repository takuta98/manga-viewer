import XCTest
@testable import MangaViewer

@MainActor
final class LibraryStoreDuplicateTests: XCTestCase {
    private var store: LibraryStore!
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("dup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        store = LibraryStore()
        for volume in store.volumes where !volume.isBundledSample {
            store.delete(volume)
        }
    }

    override func tearDown() async throws {
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
        store = nil
        scratch = nil
    }

    func testDetectDuplicateMatchesTitleAndPageCount() throws {
        let a = try importSynthetic(title: "重複テスト", pageCount: 3)
        XCTAssertNotNil(store.detectDuplicate(title: "重複テスト", pageCount: 3))
        XCTAssertEqual(store.detectDuplicate(title: "重複テスト", pageCount: 3)?.id, a.id)
        XCTAssertNil(store.detectDuplicate(title: "重複テスト", pageCount: 99))
        XCTAssertNil(store.detectDuplicate(title: "別タイトル", pageCount: 3))
    }

    func testImportURLSkipsExactDuplicate() throws {
        let first = try importSynthetic(title: "完全一致", pageCount: 2)
        let second = try importSynthetic(title: "完全一致", pageCount: 2, policy: .skipExactElseRename)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.volumes.filter { $0.title == "完全一致" }.count, 1)
    }

    func testImportURLRenamesWhenTitleMatchesDifferentPageCount() throws {
        _ = try importSynthetic(title: "同名別ページ", pageCount: 2)
        let second = try importSynthetic(title: "同名別ページ", pageCount: 4, policy: .skipExactElseRename)
        XCTAssertEqual(second.title, "同名別ページ（2）")
        XCTAssertEqual(second.pageCount, 4)
    }

    func testImportURLRenamePolicyAlwaysSuffixes() throws {
        _ = try importSynthetic(title: "リネーム方針", pageCount: 2)
        let second = try importSynthetic(title: "リネーム方針", pageCount: 2, policy: .rename)
        XCTAssertEqual(second.title, "リネーム方針（2）")
        XCTAssertNotEqual(
            store.detectDuplicate(title: "リネーム方針", pageCount: 2)?.id,
            second.id
        )
    }

    func testImportURLSkipPolicyReturnsExistingOnTitleOnly() throws {
        let first = try importSynthetic(title: "スキップ方針", pageCount: 2)
        let second = try importSynthetic(title: "スキップ方針", pageCount: 5, policy: .skip)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.volumes.filter { $0.title.hasPrefix("スキップ方針") }.count, 1)
    }

    func testUniqueTitleIncrementsSuffix() throws {
        _ = try importSynthetic(title: "連番", pageCount: 1)
        XCTAssertEqual(store.uniqueTitle("連番"), "連番（2）")
        _ = try importSynthetic(title: "連番", pageCount: 2, policy: .rename)
        XCTAssertEqual(store.uniqueTitle("連番"), "連番（3）")
    }

    private func importSynthetic(
        title: String,
        pageCount: Int,
        policy: LibraryStore.DuplicateImportPolicy = .skipExactElseRename
    ) throws -> MangaVolume {
        let dir = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 1...pageCount {
            let url = dir.appendingPathComponent(String(format: "%04d.png", i))
            try Self.minimalPNG.write(to: url)
        }
        return try store.importURL(dir, titleOverride: title, duplicatePolicy: policy)
    }

    private static let minimalPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
}
