import Foundation

enum RemoteSourceKind: String, CaseIterable, Identifiable, Codable {
    case smb, webdav, sftp, ftp, opds, s3, http
    var id: String { rawValue }
    var label: String {
        switch self {
        case .smb: return AppCopy.kindSMB
        case .webdav: return AppCopy.kindWebDAV
        case .sftp: return AppCopy.kindSFTP
        case .ftp: return AppCopy.kindFTP
        case .opds: return AppCopy.kindOPDS
        case .s3: return AppCopy.kindS3
        case .http: return AppCopy.kindHTTP
        }
    }
}

struct RemoteSource: Identifiable, Hashable {
    var id: UUID
    var kind: RemoteSourceKind
    var name: String
    var host: String
    var port: Int
    var shareOrPath: String
    var username: String
    var password: String
    var domain: String
    var region: String
    var bucket: String
    var useTLS: Bool
    var createdAt: Date
    var lastSuccessAt: Date?
    var lastBrowsePath: String?

    static func blank(_ kind: RemoteSourceKind) -> RemoteSource {
        RemoteSource(
            id: UUID(),
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
            createdAt: Date(),
            lastSuccessAt: nil,
            lastBrowsePath: nil
        )
    }

    static func defaultPort(_ kind: RemoteSourceKind) -> Int {
        switch kind {
        case .smb: return 445
        case .webdav: return 443
        case .sftp: return 22
        case .ftp: return 21
        case .opds: return 443
        case .s3: return 443
        case .http: return 443
        }
    }
}

extension RemoteSource: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, name, host, port, shareOrPath, username, password, domain, region, bucket, useTLS, createdAt, lastSuccessAt, lastBrowsePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(RemoteSourceKind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? kind.label
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? Self.defaultPort(kind)
        shareOrPath = try c.decodeIfPresent(String.self, forKey: .shareOrPath) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "us-east-1"
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        useTLS = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastSuccessAt = try c.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        lastBrowsePath = try c.decodeIfPresent(String.self, forKey: .lastBrowsePath)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(shareOrPath, forKey: .shareOrPath)
        try c.encode(username, forKey: .username)
        // パスワードは Keychain のみ。JSON には書かない。
        try c.encode(domain, forKey: .domain)
        try c.encode(region, forKey: .region)
        try c.encode(bucket, forKey: .bucket)
        try c.encode(useTLS, forKey: .useTLS)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastSuccessAt, forKey: .lastSuccessAt)
        try c.encodeIfPresent(lastBrowsePath, forKey: .lastBrowsePath)
    }
}

struct RemoteEntry: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64?
    var downloadURL: URL? = nil
}
