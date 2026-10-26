import Foundation

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
}
