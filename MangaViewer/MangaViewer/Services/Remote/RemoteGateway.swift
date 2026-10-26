import Foundation

enum RemoteError: LocalizedError {
    case message(String)
    case invalidURL
    case requestFailed(String)
    case unsupported
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .message(let s), .requestFailed(let s):
            return s
        case .invalidURL:
            return AppCopy.invalidURL
        case .unsupported:
            return AppCopy.remoteUnsupported
        case .notConfigured:
            return AppCopy.remoteNotConfigured
        }
    }
}

enum RemoteImportUnit {
    case archive(RemoteEntry)
    case imageFolder(path: String, title: String, files: [RemoteEntry])
}

enum RemoteGateway {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let s = await RemoteSourceStore.shared.hydrated(source)
        switch s.kind {
        case .smb: return try await SMBClientService.list(source: s, path: path)
        case .webdav: return try await WebDAVClient.list(source: s, path: path)
        case .sftp: return try await SFTPClientService.list(source: s, path: path)
        case .ftp: return try await FTPClient.list(source: s, path: path)
        case .opds: return try await OPDSClient.list(source: s, path: path)
        case .s3: return try await S3Client.list(source: s, path: path)
        case .http: return try await HTTPDownloadService.list(source: s, path: path)
        }
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to url: URL) async throws {
        let s = await RemoteSourceStore.shared.hydrated(source)
        switch s.kind {
        case .smb: try await SMBClientService.download(source: s, path: entry.path, to: url)
        case .webdav: try await WebDAVClient.download(source: s, entry: entry, to: url)
        case .sftp: try await SFTPClientService.download(source: s, path: entry.path, to: url)
        case .ftp: try await FTPClient.download(source: s, entry: entry, to: url)
        case .opds: try await OPDSClient.download(source: s, entry: entry, to: url)
        case .s3: try await S3Client.download(source: s, entry: entry, to: url)
        case .http: try await HTTPDownloadService.download(source: s, entry: entry, to: url)
        }
    }

    static func collectImportUnits(source: RemoteSource, folderPath: String) async throws -> [RemoteImportUnit] {
        let entries = try await list(source: source, path: folderPath)
        var units: [RemoteImportUnit] = []
        var images: [RemoteEntry] = []
        for e in entries {
            if e.isDirectory {
                let child = try await list(source: source, path: e.path)
                let childImages = child.filter { !$0.isDirectory && ComicFileProbe.isSupportedForImport($0.name) && MangaImporter.isImage(($0.name as NSString).pathExtension) }
                let archives = child.filter { !$0.isDirectory && ComicFileProbe.isSupportedForImport($0.name) && !MangaImporter.isImage(($0.name as NSString).pathExtension) }
                if !childImages.isEmpty {
                    units.append(.imageFolder(path: e.path, title: e.name, files: childImages))
                }
                for a in archives { units.append(.archive(a)) }
            } else if ComicFileProbe.isSupportedForImport(e.name) {
                if MangaImporter.isImage((e.name as NSString).pathExtension) {
                    images.append(e)
                } else {
                    units.append(.archive(e))
                }
            }
        }
        if !images.isEmpty {
            let title = (folderPath as NSString).lastPathComponent
            units.insert(.imageFolder(path: folderPath, title: title.isEmpty ? source.name : title, files: images), at: 0)
        }
        return units
    }
}
