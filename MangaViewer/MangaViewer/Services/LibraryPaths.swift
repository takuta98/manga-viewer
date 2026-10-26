import Foundation

enum LibraryPaths {
    static var root: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var catalogURL: URL {
        root.appendingPathComponent("catalog.json")
    }

    static func volumeDirectory(_ name: String) -> URL {
        let url = root.appendingPathComponent("Volumes", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
