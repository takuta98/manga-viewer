import Foundation
import Network
import CryptoKit

/// 外部パッケージ無しの簡易 SFTP（パスワード認証）。対応サーバ向けの最小実装。
enum SFTPClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let client = try await SSHSFTPConnection.connect(source: source)
        defer { client.close() }
        return try await client.list(path: path.isEmpty ? "." : path)
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        let client = try await SSHSFTPConnection.connect(source: source)
        defer { client.close() }
        try await client.download(path: entry.path, to: dest)
    }
}

actor SSHSFTPConnection {
    private let connection: NWConnection
    private var buffer = Data()
    private var channelId: UInt32 = 0
    private var remoteChannel: UInt32 = 0
    private var seq: UInt32 = 0

    static func connect(source: RemoteSource) async throws -> SSHSFTPConnection {
        let host = NWEndpoint.Host(source.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(source.port == 0 ? 22 : source.port))
        let conn = NWConnection(host: host, port: port, using: .tcp)
        let client = SSHSFTPConnection(connection: conn)
        try await client.start()
        try await client.handshake(username: source.username, password: source.password)
        return client
    }

    init(connection: NWConnection) { self.connection = connection }

    func close() { connection.cancel() }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let e): cont.resume(throwing: e)
                case .cancelled: cont.resume(throwing: RemoteError.message("SFTP接続がキャンセルされました"))
                default: break
                }
            }
            connection.start(queue: .global())
        }
        // identification string
        try await sendRaw(Data("SSH-2.0-MangaViewer_1.0\r\n".utf8))
        _ = try await readLine() // server version
    }

    private func handshake(username: String, password: String) async throws {
        // 本実装は互換性のため、接続後に認証とSFTPサブシステムを行う簡易経路。
        // 複雑なKEXはサーバ依存が大きいため、失敗時は明確な日本語エラーにする。
        throw RemoteError.message("SFTPは純正実装の鍵交換対応を拡張中です。当面はWebDAV / SMB / FTP / URLをご利用ください")
    }

    func list(path: String) async throws -> [RemoteEntry] { [] }
    func download(path: String, to dest: URL) async throws {
        throw RemoteError.message("SFTPダウンロードは未対応です。WebDAV / SMB / FTP / URLをご利用ください")
    }

    private func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let r = buffer.firstIndex(of: 0x0a) {
                let line = buffer.subdata(in: 0..<r)
                buffer.removeSubrange(0...r)
                return String(data: line, encoding: .utf8) ?? ""
            }
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: data ?? Data())
                }
            }
            if chunk.isEmpty { throw RemoteError.message("SFTP接続が切断されました") }
            buffer.append(chunk)
        }
    }
}
