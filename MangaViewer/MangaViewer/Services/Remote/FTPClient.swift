import Foundation
import Network

/// Minimal FTP LIST / RETR client (active-less PASV).
enum FTPClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let session = try await FTPSession.connect(source: source)
        defer { session.close() }
        let cwd = path.isEmpty ? (source.shareOrPath.isEmpty ? "/" : source.shareOrPath) : path
        _ = try await session.command("CWD \(cwd)")
        let listing = try await session.passiveDataString(command: "LIST")
        return parseList(listing, base: cwd)
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let session = try await FTPSession.connect(source: source)
        defer { session.close() }
        let dir = (path as NSString).deletingLastPathComponent
        let file = (path as NSString).lastPathComponent
        if !dir.isEmpty && dir != "." {
            _ = try await session.command("CWD \(dir)")
        }
        let data = try await session.passiveData(command: "RETR \(file)")
        try data.write(to: local)
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
}

final class FTPSession {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ftp.session")

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func connect(source: RemoteSource) async throws -> FTPSession {
        let host = source.host.replacingOccurrences(of: "ftp://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let err): cont.resume(throwing: err)
                case .cancelled: cont.resume(throwing: RemoteError.requestFailed("FTP cancelled"))
                default: break
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
        let pasv = try await command("PASV")
        let (host, port) = try parsePASV(pasv)
        let dataConn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            dataConn.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let err): cont.resume(throwing: err)
                default: break
                }
            }
            dataConn.start(queue: queue)
        }
        _ = try await command(cmd)
        let data = try await readAll(from: dataConn)
        dataConn.cancel()
        _ = try? await readReply()
        return data
    }

    func close() {
        connection.cancel()
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
            if let chunk { all.append(chunk) }
            if chunk == nil || chunk?.isEmpty == true { break }
        }
        return all
    }

    private func parsePASV(_ reply: String) throws -> (String, UInt16) {
        guard let open = reply.firstIndex(of: "("), let close = reply.firstIndex(of: ")") else {
            throw RemoteError.requestFailed("PASV parse failed")
        }
        let inner = reply[reply.index(after: open)..<close]
        let parts = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 6 else { throw RemoteError.requestFailed("PASV parse failed") }
        let host = "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
        let port = UInt16(parts[4] * 256 + parts[5])
        return (host, port)
    }
}
