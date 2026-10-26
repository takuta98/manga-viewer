import Foundation
import Citadel
import NIO

enum SFTPClientService {
    private static let readChunkBytes: UInt32 = 256 * 1024

    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        try await SFTPSessionPool.shared.withSession(source: source) { sftp in
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
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        try await SFTPSessionPool.shared.withSession(source: source) { sftp in
            try? FileManager.default.removeItem(at: local)
            FileManager.default.createFile(atPath: local.path, contents: nil)
            let handle = try FileHandle(forWritingTo: local)
            do {
                try await sftp.withFile(filePath: path, flags: .read) { file in
                    var offset: UInt64 = 0
                    while true {
                        var buffer = try await file.read(from: offset, length: readChunkBytes)
                        let count = buffer.readableBytes
                        if count == 0 { break }
                        guard let bytes = buffer.readBytes(length: count) else { break }
                        try handle.write(contentsOf: bytes)
                        offset += UInt64(count)
                    }
                }
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: local)
                throw error
            }
        }
    }

    fileprivate static func connect(_ source: RemoteSource) async throws -> SSHClient {
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

    fileprivate static func sessionKey(for source: RemoteSource) -> String {
        "\(source.host)|\(source.port ?? 22)|\(source.username)|\(source.password)"
    }
}

/// フォルダ巡回・連続ダウンロードで SSH/SFTP を張り直さない。
private actor SFTPSessionPool {
    static let shared = SFTPSessionPool()

    private struct Slot {
        let key: String
        let client: SSHClient
        let sftp: SFTPClient
        var lastUsed: Date
    }

    private var slot: Slot?
    private let idleTTL: TimeInterval = 90

    func withSession<T>(source: RemoteSource, _ body: (SFTPClient) async throws -> T) async throws -> T {
        let key = SFTPClientService.sessionKey(for: source)
        let sftp = try await acquire(key: key, source: source)
        do {
            let value = try await body(sftp)
            if var current = slot, current.key == key {
                current.lastUsed = Date()
                slot = current
            }
            return value
        } catch {
            await invalidate()
            throw error
        }
    }

    private func acquire(key: String, source: RemoteSource) async throws -> SFTPClient {
        if let current = slot {
            if current.key == key, Date().timeIntervalSince(current.lastUsed) < idleTTL {
                return current.sftp
            }
            await drop(current)
            slot = nil
        }

        let client = try await SFTPClientService.connect(source)
        do {
            let sftp = try await client.openSFTP()
            slot = Slot(key: key, client: client, sftp: sftp, lastUsed: Date())
            return sftp
        } catch {
            try? await client.close()
            throw error
        }
    }

    private func invalidate() async {
        guard let current = slot else { return }
        slot = nil
        await drop(current)
    }

    private func drop(_ current: Slot) async {
        try? await current.sftp.close()
        try? await current.client.close()
    }
}
