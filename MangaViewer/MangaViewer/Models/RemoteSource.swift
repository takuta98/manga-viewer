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

struct RemoteSource: Identifiable, Hashable {
    var id: String
    var kind: RemoteSourceKind
    var name: String
    var host: String
    var port: Int?
    var shareOrPath: String
    var username: String
    /// メモリ上のみ。永続化は Keychain。
    var password: String
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

extension RemoteSource: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, name, host, port, shareOrPath, username, password, domain, region, bucket, useTLS, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(RemoteSourceKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        shareOrPath = try c.decodeIfPresent(String.self, forKey: .shareOrPath) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        // 旧 JSON からの移行用。通常は空で Keychain から読む。
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket)
        useTLS = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encodeIfPresent(port, forKey: .port)
        try c.encode(shareOrPath, forKey: .shareOrPath)
        try c.encode(username, forKey: .username)
        // パスワードは JSON に書かない
        try c.encodeIfPresent(domain, forKey: .domain)
        try c.encodeIfPresent(region, forKey: .region)
        try c.encodeIfPresent(bucket, forKey: .bucket)
        try c.encode(useTLS, forKey: .useTLS)
        try c.encode(createdAt, forKey: .createdAt)
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
    static let supportedArchiveExtensions = ["cbz", "zip", "pdf"]

    static func fileExtension(of name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    static func isSupportedArchive(_ name: String) -> Bool {
        supportedArchiveExtensions.contains(fileExtension(of: name))
    }

    static func isSupportedImage(_ name: String) -> Bool {
        imageExtensions.contains(fileExtension(of: name))
    }

    static func isImportableFile(_ name: String) -> Bool {
        let ext = fileExtension(of: name)
        return archiveExtensions.contains(ext) || imageExtensions.contains(ext)
    }

    static func isSupportedForImport(_ name: String) -> Bool {
        isSupportedArchive(name) || isSupportedImage(name)
    }
}
