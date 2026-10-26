import XCTest
@testable import MangaViewer

@MainActor
final class ReadingProgressTests: XCTestCase {
    func testPercentUsesPageCount() {
        let volume = MangaVolume(
            id: UUID(),
            title: "t",
            directoryName: "d",
            pageFileNames: ["a", "b", "c", "d"],
            coverFileName: nil,
            direction: .rtl,
            importedAt: Date(),
            isBundledSample: false
        )
        let progress = ReadingProgress.shared
        progress.setPageIndex(1, for: volume.id)
        XCTAssertEqual(progress.percent(for: volume), 50)
        progress.clear(for: volume.id)
    }
}
