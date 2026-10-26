import Foundation

enum ImportStaging {
    static func fileURL(named name: String) throws -> URL {
        let session = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let safe = (name as NSString).lastPathComponent
        return session.appendingPathComponent(safe.isEmpty ? "download.bin" : safe)
    }

    static func removeSession(containing url: URL) {
        let session = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: session)
    }
}
