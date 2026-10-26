import Foundation

/// 取り込み用一時置き場。
/// ルール: ユーザー向け名はファイル名そのもの。UUID は親ディレクトリにだけ置く。
/// `UUID + "-" + fileName` をファイル名にしてはいけない（タイトル汚染の温床）。
enum ImportStaging {
    private static let rootName = "manga-import-staging"

    /// `.../manga-import-staging/<session>/<fileName>` を返す。`fileName` はクリーンな表示名由来。
    static func fileURL(named fileName: String) throws -> URL {
        let cleanName = sanitizedFileName(fileName)
        let dir = try sessionDirectory()
        return dir.appendingPathComponent(cleanName, isDirectory: false)
    }

    /// 画像フォルダ取込用の空ディレクトリ。ディレクトリ名もユーザー向けタイトルのみ。
    static func directoryURL(named folderTitle: String) throws -> URL {
        let cleanName = sanitizedFileName(folderTitle)
        let dir = try sessionDirectory().appendingPathComponent(cleanName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func removeSession(containing url: URL) {
        // staging/<session>/... の session ディレクトリまで消す
        var current = url
        let fm = FileManager.default
        for _ in 0..<3 {
            let parent = current.deletingLastPathComponent()
            if parent.lastPathComponent == rootName {
                try? fm.removeItem(at: current)
                return
            }
            current = parent
        }
        try? fm.removeItem(at: url)
    }

    private static func sessionDirectory() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true)
        let session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        return session
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        var name = UserFacingText.clean((raw as NSString).lastPathComponent)
        // ファイル名に使えない文字を避ける
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        name = name.components(separatedBy: invalid).joined(separator: "-")
        if name.isEmpty { name = "import" }
        return name
    }
}
