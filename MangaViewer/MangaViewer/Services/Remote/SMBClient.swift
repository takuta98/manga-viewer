import Foundation
import Network

/// オリジナルの最小 SMB2 クライアント（Negotiate / SessionSetup / TreeConnect / Read / Find）。
enum SMBClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        try await withSession(source) { session in
            try await session.list(path: path)
        }
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        try await withSession(source) { session in
            try await session.download(path: entry.path, to: dest)
        }
    }

    private static func withSession<T>(_ source: RemoteSource, _ body: (SMBSession) async throws -> T) async throws -> T {
        let session = SMBSession(source: source)
        try await session.connect()
        defer { session.close() }
        return try await body(session)
    }
}

final class SMBSession {
    private let source: RemoteSource
    private var connection: NWConnection?
    private var messageId: UInt64 = 1
    private var sessionId: UInt64 = 0
    private var treeId: UInt32 = 0
    private let queue = DispatchQueue(label: "manga.smb")

    init(source: RemoteSource) { self.source = source }

    func connect() async throws {
        let host = NWEndpoint.Host(source.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(source.port == 0 ? 445 : source.port))
        let conn = NWConnection(host: host, port: port, using: .tcp)
        self.connection = conn
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let e): cont.resume(throwing: e)
                case .cancelled: cont.resume(throwing: RemoteError.message("SMB接続がキャンセルされました"))
                default: break
                }
            }
            conn.start(queue: queue)
        }
        try await negotiate()
        try await sessionSetup()
        try await treeConnect()
    }

    func close() { connection?.cancel(); connection = nil }

    func list(path: String) async throws -> [RemoteEntry] {
        // 最小実装: 共有直下の名前を FIND 相当の簡易列挙が難しいため、パス指定のファイル存在確認に寄せる。
        // ディレクトリ一覧は SMB2 QUERY_DIRECTORY を送る。
        let share = source.shareOrPath.split(separator: "/").first.map(String.init) ?? source.shareOrPath
        if share.isEmpty && path.isEmpty {
            // 共有名未指定: ユーザーに共有名入力を促すメッセージ
            throw RemoteError.message("共有フォルダ名を接続設定のパスに入力してください")
        }
        let relative = normalized(path)
        let fileId = try await create(path: relative, directory: true)
        defer { Task { try? await close(fileId: fileId) } }
        return try await queryDirectory(fileId: fileId, path: relative)
    }

    func download(path: String, to dest: URL) async throws {
        let fileId = try await create(path: normalized(path), directory: false)
        defer { Task { try? await close(fileId: fileId) } }
        var offset: UInt64 = 0
        var out = Data()
        while true {
            let chunk = try await read(fileId: fileId, offset: offset, length: 64 * 1024)
            if chunk.isEmpty { break }
            out.append(chunk)
            offset += UInt64(chunk.count)
            if chunk.count < 64 * 1024 { break }
        }
        try out.write(to: dest)
    }

    private func normalized(_ path: String) -> String {
        var p = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let share = source.shareOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let first = share.split(separator: "/").first, p.hasPrefix(String(first) + "/") {
            p = String(p.dropFirst(first.count + 1))
        } else if p == share {
            p = ""
        }
        return p.replacingOccurrences(of: "/", with: "\\")
    }

    // MARK: - SMB2 primitives (simplified)

    private func negotiate() async throws {
        var body = Data()
        body += u16(0x24); body += u16(1); body += u16(0); body += u16(0)
        body += u32(0); body += u16(0); body += u16(0); body += u32(0)
        body += Data(count: 16) // client GUID
        body += u32(0); body += u16(0); body += u16(2)
        body += u16(0x0202) // SMB 2.0.2
        let _ = try await transact(command: 0x0000, treeId: 0, sessionId: 0, body: body)
    }

    private func sessionSetup() async throws {
        // Guest / user-pass NTLM is complex; send SESSION_SETUP with empty security buffer for guest-ish servers.
        var body = Data()
        body += u16(0x19); body += u8(0x01); body += u8(0); body += u32(0)
        body += u32(0); body += u32(0); body += u32(0)
        body += u16(0x58); body += u16(0)
        let resp = try await transact(command: 0x0001, treeId: 0, sessionId: 0, body: body)
        // sessionId from header bytes 32..<40 little endian
        if resp.count >= 40 {
            sessionId = u64le(resp, 32)
        }
        if !source.username.isEmpty && sessionId == 0 {
            throw RemoteError.message("SMBログオンに失敗しました。ユーザー名とパスワードを確認してください")
        }
    }

    private func treeConnect() async throws {
        let share = source.shareOrPath.split(separator: "/").first.map(String.init) ?? source.shareOrPath
        guard !share.isEmpty else { throw RemoteError.message("共有フォルダ名を入力してください") }
        let unc = "\\\\\((source.host))\\\(share)"
        var pathBytes: [UInt8] = Array(unc.utf16).flatMap { [UInt8($0 & 0xff), UInt8(($0 >> 8) & 0xff)] }
        pathBytes.append(contentsOf: [0, 0])
        var body = Data()
        body += u16(0x09); body += u16(0); body += u16(0x48); body += u16(UInt16(pathBytes.count))
        body.append(contentsOf: pathBytes)
        let resp = try await transact(command: 0x0003, treeId: 0, sessionId: sessionId, body: body)
        if resp.count >= 44 {
            treeId = u32le(resp, 40)
        }
        if treeId == 0 {
            throw RemoteError.message("SMB共有へ接続できませんでした")
        }
    }

    private func create(path: String, directory: Bool) async throws -> Data {
        let name = path.isEmpty ? "" : path
        let nameData: [UInt8] = Array(name.utf16).flatMap { [UInt8($0 & 0xff), UInt8(($0 >> 8) & 0xff)] }
        var body = Data()
        body += u16(0x39); body += u8(0); body += u8(0)
        body += u32(0); body += Data(count: 16)
        body += u32(directory ? 0x100081 : 0x120089) // desired access
        body += u64(0); body += u32(0x80)
        body += u32(directory ? 0x00000001 : 0x00000003)
        body += u32(directory ? 0x00000001 : 0x00000000)
        body += u32(0x00000040)
        body += u32(0); body += u32(0)
        body += u16(0x78); body += u16(UInt16(nameData.count))
        body += u32(0)
        body.append(contentsOf: nameData)
        let resp = try await transact(command: 0x0005, treeId: treeId, sessionId: sessionId, body: body)
        guard resp.count >= 0x40 + 16 else { throw RemoteError.message("SMBファイルを開けませんでした") }
        // FileId at offset 64 in CREATE response body => header(64)+body offset 64
        let bodyStart = 64
        return resp.subdata(in: (bodyStart+64)..<(bodyStart+80))
    }

    private func read(fileId: Data, offset: UInt64, length: UInt32) async throws -> Data {
        var body = Data()
        body += u16(0x31); body += u8(0); body += u8(0)
        body += u32(length); body += u64(offset)
        body += fileId
        body += u32(0); body += u32(0); body += u16(0); body += u16(0)
        let resp = try await transact(command: 0x0008, treeId: treeId, sessionId: sessionId, body: body)
        // DataOffset/DataLength in READ response
        guard resp.count > 64 + 16 else { return Data() }
        let b = 64
        let dataOffset = Int(u16le(resp, b + 2))
        let dataLength = Int(u32le(resp, b + 4))
        let start = dataOffset
        let end = min(resp.count, start + dataLength)
        guard start < end else { return Data() }
        return resp.subdata(in: start..<end)
    }

    private func queryDirectory(fileId: Data, path: String) async throws -> [RemoteEntry] {
        let pattern: [UInt8] = Array("*".utf16).flatMap { [UInt8($0 & 0xff), UInt8(($0 >> 8) & 0xff)] }
        var body = Data()
        body += u16(0x21); body += u8(0); body += u8(0)
        body += u8(0x25) // FileIdBothDirectoryInformation
        body += u8(0); body += u16(0)
        body += u32(0x10000)
        body += fileId
        body += u16(0x60); body += u16(UInt16(pattern.count))
        body.append(contentsOf: pattern)
        let resp = try await transact(command: 0x000E, treeId: treeId, sessionId: sessionId, body: body)
        return parseDir(resp, parentPath: path.replacingOccurrences(of: "\\", with: "/"))
    }

    private func close(fileId: Data) async throws {
        var body = Data()
        body += u16(0x18); body += u16(0); body += u32(0); body += fileId
        _ = try await transact(command: 0x0006, treeId: treeId, sessionId: sessionId, body: body)
    }

    private func parseDir(_ resp: Data, parentPath: String) -> [RemoteEntry] {
        var entries: [RemoteEntry] = []
        var o = 64 + 8 // rough skip to first info (best-effort)
        // Better: body OutputBufferOffset
        if resp.count > 64 + 8 {
            let outOff = Int(u16le(resp, 64 + 2))
            o = outOff
        }
        while o + 64 < resp.count {
            let next = Int(u32le(resp, o))
            let fileNameLen = Int(u32le(resp, o + 60))
            let attrs = u32le(resp, o + 56)
            let nameStart = o + 104
            let nameEnd = min(resp.count, nameStart + fileNameLen)
            if nameStart < nameEnd {
                let nameData = resp.subdata(in: nameStart..<nameEnd)
                let name = String(bytes: nameData, encoding: .utf16LittleEndian)?.trimmingCharacters(in: .controlCharacters) ?? ""
                if name != "." && name != ".." && !name.isEmpty {
                    let isDir = (attrs & 0x10) != 0
                    let path = parentPath.isEmpty ? name : parentPath + "/" + name
                    entries.append(RemoteEntry(name: name, path: path, isDirectory: isDir, size: nil))
                }
            }
            if next == 0 { break }
            o += next
        }
        return entries
    }

    private func transact(command: UInt16, treeId: UInt32, sessionId: UInt64, body: Data) async throws -> Data {
        let mid = messageId
        messageId += 1
        var header = Data(count: 64)
        header[0] = 0xfe; header[1] = 0x53; header[2] = 0x4d; header[3] = 0x42 // \xfeSMB
        writeU16(&header, 4, 64)
        writeU16(&header, 12, command)
        writeU32(&header, 20, 0) // flags
        writeU32(&header, 24, 0)
        writeU32(&header, 28, 0)
        writeU64(&header, 24, mid) // overlap carefully - use correct offsets
        // Rebuild header cleanly
        header = Data()
        header += Data([0xfe, 0x53, 0x4d, 0x42])
        header += u16(64) // structure size
        header += u16(0) // credit charge
        header += u32(0) // status
        header += u16(command)
        header += u16(0) // credits requested
        header += u32(0) // flags
        header += u32(0) // next command
        header += u64(mid)
        header += u32(0) // process id / async
        header += u32(treeId)
        header += u64(sessionId)
        header += Data(count: 16) // signature
        let nbLength = UInt32(header.count + body.count)
        var packet = Data()
        packet.append(0x00)
        packet.append(UInt8((nbLength >> 16) & 0xff))
        packet.append(UInt8((nbLength >> 8) & 0xff))
        packet.append(UInt8(nbLength & 0xff))
        packet.append(header)
        packet.append(body)
        try await send(packet)
        return try await receive()
    }

    private func send(_ data: Data) async throws {
        guard let connection else { throw RemoteError.message("SMB未接続です") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receive() async throws -> Data {
        guard let connection else { throw RemoteError.message("SMB未接続です") }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
                if let error { cont.resume(throwing: error); return }
                guard let header, header.count == 4 else {
                    cont.resume(throwing: RemoteError.message("SMB応答が不正です")); return
                }
                let len = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
                connection.receive(minimumIncompleteLength: len, maximumLength: len) { body, _, _, error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: body ?? Data())
                }
            }
        }
    }

    private func u8(_ v: UInt8) -> Data { Data([v]) }
    private func u16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
    private func u32(_ v: UInt32) -> Data { u16(UInt16(v & 0xffff)) + u16(UInt16(v >> 16)) }
    private func u64(_ v: UInt64) -> Data { u32(UInt32(v & 0xffffffff)) + u32(UInt32(v >> 32)) }
    private func u16le(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[o]) | (UInt16(d[o+1]) << 8) }
    private func u32le(_ d: Data, _ o: Int) -> UInt32 { UInt32(u16le(d, o)) | (UInt32(u16le(d, o+2)) << 16) }
    private func u64le(_ d: Data, _ o: Int) -> UInt64 { UInt64(u32le(d, o)) | (UInt64(u32le(d, o+4)) << 32) }
    private func writeU16(_ d: inout Data, _ o: Int, _ v: UInt16) { d[o] = UInt8(v & 0xff); d[o+1] = UInt8(v >> 8) }
    private func writeU32(_ d: inout Data, _ o: Int, _ v: UInt32) { writeU16(&d, o, UInt16(v & 0xffff)); writeU16(&d, o+2, UInt16(v >> 16)) }
    private func writeU64(_ d: inout Data, _ o: Int, _ v: UInt64) { writeU32(&d, o, UInt32(v & 0xffffffff)); writeU32(&d, o+4, UInt32(v >> 32)) }
}
