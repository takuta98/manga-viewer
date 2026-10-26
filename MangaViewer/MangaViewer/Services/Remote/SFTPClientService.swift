import Foundation
import Citadel
import NIO

enum SFTPClientService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let client = try await connect(source)
        defer { Task { try? await client.close() } }
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }
        let dir = path.isEmpty ? (source.shareOrPath.isEmpty ? "." : source.shareOrPath) : path
        let names = try await sftp.listDirectory(atPath: dir)
        var entries: [RemoteEntry] = []
        for nameMsg in names {
            for component in nameMsg.components {
                let name = component.filename
                if name == "." || name == ".." { continue }
                let child = dir == "." ? name : "\(dir)/\(name)"
                let isDir = component.longname.hasPrefix("d")
                let size = component.attributes.size.map { Int64($0) }
                entries.append(
                    RemoteEntry(name: name, path: child, isDirectory: isDir, size: size, downloadURL: nil)
                )
            }
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let client = try await connect(source)
        defer { Task { try? await client.close() } }
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }
        let buffer: ByteBuffer = try await sftp.withFile(filePath: path, flags: .read) { file in
            try await file.readAll()
        }
        var mutable = buffer
        let bytes = mutable.readBytes(length: mutable.readableBytes) ?? []
        try Data(bytes).write(to: local)
    }

    private static func connect(_ source: RemoteSource) async throws -> SSHClient {
        var host = source.host
            .replacingOccurrences(of: "sftp://", with: "")
            .replacingOccurrences(of: "ssh://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        let settings = SSHClientSettings(
            host: host,
            port: source.port ?? 22,
            authenticationMethod: {
                .passwordBased(
                    username: source.username.isEmpty ? "anonymous" : source.username,
                    password: source.password
                )
            },
            hostKeyValidator: .acceptAnything()
        )
        return try await SSHClient.connect(to: settings)
    }
}
