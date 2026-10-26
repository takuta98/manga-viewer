import Foundation

enum RemoteSourceKind: String, Codable, CaseIterable, Identifiable {
    case files
    case smb
    case webdav
    case ftp
    case sftp
    case opds
    case httpURL
    case s3
    case wifiTransfer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .files: return "Files / iCloud / クラウド"
        case .smb: return "SMB (NAS)"
        case .webdav: return "WebDAV"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .opds: return "OPDS / Komga / Kavita"
        case .httpURL: return "URL ダウンロード"
        case .s3: return "S3 / MinIO"
        case .wifiTransfer: return "Wi-Fi 転送"
        }
    }

    var systemImage: String {
        switch self {
        case .files: return "folder"
        case .smb: return "externaldrive.connected.to.line.below"
        case .webdav: return "globe"
        case .ftp: return "server.rack"
        case .sftp: return "lock.laptopcomputer"
        case .opds: return "books.vertical"
        case .httpURL: return "link"
        case .s3: return "cylinder.split.1x2"
        case .wifiTransfer: return "wifi"
        }
    }
}

struct RemoteSource: Identifiable, Codable, Hashable {
    var id: String
    var kind: RemoteSourceKind
    var name: String
    /// Host or base URL (scheme optional depending on kind).
    var host: String
    var port: Int?
    var shareOrPath: String
    var username: String
    /// Stored in Keychain in production; UserDefaults for MVP (device-local).
    var password: String
    /// SMB のドメイン / ワークグループ（空なら省略）。既存 JSON 互換のため Optional。
    var domain: String?
    var region: String?
    var bucket: String?
    var useTLS: Bool
    var createdAt: Date

    static func blank(_ kind: RemoteSourceKind) -> RemoteSource {
        RemoteSource(
            id: UUID().uuidString,
            kind: kind,
            name: kind.label,
            host: "",
            port: defaultPort(kind),
            shareOrPath: "",
            username: "",
            password: "",
            domain: "",
            region: "us-east-1",
            bucket: "",
            useTLS: kind != .ftp && kind != .smb,
            createdAt: Date()
        )
    }

    static func defaultPort(_ kind: RemoteSourceKind) -> Int? {
        switch kind {
        case .smb: return 445
        case .webdav: return 443
        case .ftp: return 21
        case .sftp: return 22
        case .opds: return 443
        case .s3: return 443
        default: return nil
        }
    }
}

struct RemoteEntry: Identifiable, Hashable {
    var id: String { path + name }
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64?
    var downloadURL: URL?
}

enum ComicFileProbe {
    static let archiveExtensions = ["cbz", "zip", "pdf", "cbr", "rar", "cb7", "7z", "epub"]
    static let imageExtensions = ["jpg", "jpeg", "png", "webp", "gif", "heic", "bmp", "avif"]

    static func isImportableFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return archiveExtensions.contains(ext) || imageExtensions.contains(ext)
    }

    static func isSupportedForImport(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        // CBR/RAR/7z listed for UI but may fail until decoder present.
        return ["cbz", "zip", "pdf"].contains(ext) || imageExtensions.contains(ext)
    }
}
