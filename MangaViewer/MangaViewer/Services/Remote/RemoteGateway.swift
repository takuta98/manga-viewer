import Foundation

enum RemoteImportUnit: Sendable {
    case archive(RemoteEntry)
    case imageFolder(title: String, images: [RemoteEntry])

    var sortKey: String {
        switch self {
        case .archive(let e): return e.path
        case .imageFolder(_, let images): return images.first?.path ?? ""
        }
    }

    var displayName: String {
        switch self {
        case .archive(let e): return e.name
        case .imageFolder(let title, _): return title
        }
    }
}

enum RemoteGateway {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        switch source.kind {
        case .smb: return try await SMBClientService.list(source: source, path: path)
        case .webdav: return try await WebDAVClient.list(source: source, path: path)
        case .ftp: return try await FTPClient.list(source: source, path: path)
        case .sftp: return try await SFTPClientService.list(source: source, path: path)
        case .opds: return try await OPDSClient.list(source: source, path: path)
        case .s3: return try await S3Client.list(source: source, path: path)
        case .files, .httpURL, .wifiTransfer:
            throw RemoteError.unsupported
        }
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to local: URL) async throws {
        switch source.kind {
        case .smb:
            try await SMBClientService.download(source: source, path: entry.path, to: local)
        case .webdav:
            try await WebDAVClient.download(source: source, path: entry.path, to: local)
        case .ftp:
            try await FTPClient.download(source: source, path: entry.path, to: local)
        case .sftp:
            try await SFTPClientService.download(source: source, path: entry.path, to: local)
        case .opds:
            try await OPDSClient.download(source: source, entry: entry, to: local)
        case .s3:
            try await S3Client.download(source: source, path: entry.path, to: local)
        case .httpURL:
            try await HTTPDownloadService.download(
                urlString: entry.downloadURL?.absoluteString ?? entry.path,
                username: source.username,
                password: source.password,
                to: local
            )
        case .files, .wifiTransfer:
            throw RemoteError.unsupported
        }
    }

    /// フォルダ取込単位。アーカイブは1ファイル1冊、画像群はディレクトリ単位で1冊。
    static func collectImportUnits(source: RemoteSource, path: String) async throws -> [RemoteImportUnit] {
        var archives: [RemoteEntry] = []
        var imagesByDir: [String: [RemoteEntry]] = [:]
        try await walk(source: source, path: path) { entry in
            if ComicFileProbe.isSupportedArchive(entry.name) {
                archives.append(entry)
            } else if ComicFileProbe.isSupportedImage(entry.name) {
                let parent = (entry.path as NSString).deletingLastPathComponent
                imagesByDir[parent, default: []].append(entry)
            }
        }
        var units: [RemoteImportUnit] = archives.map { .archive($0) }
        for (dir, images) in imagesByDir {
            let sorted = images.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            let rawTitle: String
            if dir.isEmpty {
                rawTitle = (path as NSString).lastPathComponent
            } else {
                rawTitle = (dir as NSString).lastPathComponent
            }
            let title = rawTitle.isEmpty ? "無題" : rawTitle
            units.append(.imageFolder(title: title, images: sorted))
        }
        return units.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
    }

    private static func walk(
        source: RemoteSource,
        path: String,
        visit: (RemoteEntry) -> Void
    ) async throws {
        let entries = try await list(source: source, path: path)
        for entry in entries {
            if entry.isDirectory {
                try await walk(source: source, path: entry.path, visit: visit)
            } else {
                visit(entry)
            }
        }
    }
}
