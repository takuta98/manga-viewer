import Foundation
import Network

/// Minimal FTP LIST / RETR client (active-less PASV).
enum FTPClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        try await FTPSessionPool.shared.withSession(source: source) { session in
            let cwd = path.isEmpty ? (source.shareOrPath.isEmpty ? "/" : source.shareOrPath) : path
            _ = try await session.command("CWD \(cwd)")
            let listing = try await session.passiveDataString(command: "LIST")
            return parseList(listing, base: cwd)
        }
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        try await FTPSessionPool.shared.withSession(source: source) { session in
            let dir = (path as NSString).deletingLastPathComponent
            let file = (path as NSString).lastPathComponent
            if !dir.isEmpty && dir != "." {
                _ = try await session.command("CWD \(dir)")
            }
            try await session.passiveDownload(command: "RETR \(file)", to: local)
        }
    }

    static func parsePASV(_ reply: String) throws -> (String, UInt16) {
        guard let open = reply.firstIndex(of: "("), let close = reply.firstIndex(of: ")") else {
            throw RemoteError.requestFailed("PASV 応答の解析に失敗しました")
        }
        let inner = reply[reply.index(after: open)..<close]
        let parts = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 6 else { throw RemoteError.requestFailed("PASV 応答の解析に失敗しました") }
        let host = "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
        let port = UInt16(parts[4] * 256 + parts[5])
        return (host, port)
    }

    private static func parseList(_ text: String, base: String) -> [RemoteEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { lineSub -> RemoteEntry? in
            let line = String(lineSub)
            guard !line.isEmpty else { return nil }
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 9 else {
                // Windows-style or name-only
                let name = parts.last ?? line
                if name == "." || name == ".." { return nil }
                let isDir = line.lowercased().contains("<dir>")
                let path = base.hasSuffix("/") ? base + name : base + "/" + name
                return RemoteEntry(name: name, path: path, isDirectory: isDir, size: nil, downloadURL: nil)
            }
            let perms = parts[0]
            let isDir = perms.hasPrefix("d")
            let name = parts[8...].joined(separator: " ")
            if name == "." || name == ".." { return nil }
            let size = Int64(parts[4])
            let path = base.hasSuffix("/") ? base + name : "\(base)/\(name)"
            return RemoteEntry(name: name, path: path, isDirectory: isDir, size: size, downloadURL: nil)
        }
    }

    fileprivate static func sessionKey(for source: RemoteSource) -> String {
        "\(source.host)|\(source.port ?? 21)|\(source.username)|\(source.password)"
    }
}

final class FTPSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ftp.session")

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func connect(source: RemoteSource) async throws -> FTPSession {
        var host = source.host.replacingOccurrences(of: "ftp://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        let port = NWEndpoint.Port(rawValue: UInt16(source.port ?? 21)) ?? .init(integerLiteral: 21)
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let session = FTPSession(connection: conn)
        try await session.start()
        _ = try await session.readReply() // banner
        if !source.username.isEmpty {
            _ = try await session.command("USER \(source.username)")
            _ = try await session.command("PASS \(source.password)")
        } else {
            _ = try await session.command("USER anonymous")
            _ = try await session.command("PASS anonymous@")
        }
        _ = try await session.command("TYPE I")
        return session
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = OnceResume()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume { cont.resume() }
                case .failed(let err):
                    box.resume { cont.resume(throwing: err) }
                case .cancelled:
                    box.resume { cont.resume(throwing: RemoteError.requestFailed("FTP 接続がキャンセルされました")) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func command(_ cmd: String) async throws -> String {
        try await send("\(cmd)\r\n")
        return try await readReply()
    }

    func passiveDataString(command cmd: String) async throws -> String {
        let data = try await passiveData(command: cmd)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func passiveData(command cmd: String) async throws -> Data {
        let dataConn = try await openPassiveDataConnection()
        _ = try await command(cmd)
        let data = try await readAll(from: dataConn)
        dataConn.cancel()
        _ = try? await readReply()
        return data
    }

    /// RETR をローカルファイルへ逐次書き込み（全体を Data に載せない）。
    func passiveDownload(command cmd: String, to local: URL) async throws {
        let dataConn = try await openPassiveDataConnection()
        do {
            _ = try await command(cmd)
            try? FileManager.default.removeItem(at: local)
            FileManager.default.createFile(atPath: local.path, contents: nil)
            let handle = try FileHandle(forWritingTo: local)
            do {
                try await streamAll(from: dataConn, into: handle)
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: local)
                throw error
            }
            dataConn.cancel()
            _ = try? await readReply()
        } catch {
            dataConn.cancel()
            throw error
        }
    }

    func close() {
        connection.cancel()
    }

    private func openPassiveDataConnection() async throws -> NWConnection {
        let pasv = try await command("PASV")
        let (host, port) = try FTPClient.parsePASV(pasv)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RemoteError.requestFailed("PASV 応答の解析に失敗しました")
        }
        let dataConn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = OnceResume()
            dataConn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume { cont.resume() }
                case .failed(let err):
                    box.resume { cont.resume(throwing: err) }
                case .cancelled:
                    box.resume { cont.resume(throwing: RemoteError.requestFailed("FTP 接続がキャンセルされました")) }
                default:
                    break
                }
            }
            dataConn.start(queue: queue)
        }
        return dataConn
    }

    private func send(_ text: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func readReply() async throws -> String {
        var collected = Data()
        while true {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, _, error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: content ?? Data())
                }
            }
            collected.append(chunk)
            guard let text = String(data: collected, encoding: .utf8) else { continue }
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            if let last = lines.last, last.count >= 4, last[last.index(last.startIndex, offsetBy: 3)] == " " {
                return text
            }
            if chunk.isEmpty { return text }
        }
    }

    private func readAll(from conn: NWConnection) async throws -> Data {
        var all = Data()
        while true {
            let chunk: Data? = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { content, _, isComplete, error in
                    if let error { cont.resume(throwing: error); return }
                    if isComplete { cont.resume(returning: content); return }
                    cont.resume(returning: content)
                }
            }
            if let chunk, !chunk.isEmpty { all.append(chunk) }
            if chunk == nil || chunk?.isEmpty == true { break }
        }
        return all
    }

    private func streamAll(from conn: NWConnection, into handle: FileHandle) async throws {
        while true {
            let chunk: Data? = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { content, _, isComplete, error in
                    if let error { cont.resume(throwing: error); return }
                    if isComplete { cont.resume(returning: content); return }
                    cont.resume(returning: content)
                }
            }
            if let chunk, !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            if chunk == nil || chunk?.isEmpty == true { break }
        }
    }
}

/// NWConnection の state 更新で continuation を二重 resume しない。
private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

/// 同一ホストへの連続 LIST / RETR で制御接続を張り直さない。
private actor FTPSessionPool {
    static let shared = FTPSessionPool()

    private struct Slot {
        let key: String
        let session: FTPSession
        var lastUsed: Date
    }

    private var slot: Slot?
    private let idleTTL: TimeInterval = 90

    func withSession<T>(source: RemoteSource, _ body: (FTPSession) async throws -> T) async throws -> T {
        let key = FTPClient.sessionKey(for: source)
        let session = try await acquire(key: key, source: source)
        do {
            let value = try await body(session)
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

    private func acquire(key: String, source: RemoteSource) async throws -> FTPSession {
        if let current = slot {
            if current.key == key, Date().timeIntervalSince(current.lastUsed) < idleTTL {
                return current.session
            }
            current.session.close()
            slot = nil
        }
        let session = try await FTPSession.connect(source: source)
        slot = Slot(key: key, session: session, lastUsed: Date())
        return session
    }

    private func invalidate() async {
        guard let current = slot else { return }
        slot = nil
        current.session.close()
    }
}
