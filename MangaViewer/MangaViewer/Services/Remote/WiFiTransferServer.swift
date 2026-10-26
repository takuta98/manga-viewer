import Foundation
import Network
import Darwin

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published var addressText: String = AppCopy.wifiStarting
    @Published var statusText: String = AppCopy.wifiWaiting
    @Published var lastSavedURL: URL?
    @Published var lastSavedName: String?

    /// 受信ファイルを渡す。呼び出し側で本棚へ反映する。
    var onFileReceived: ((URL) -> Void)?

    private var listener: NWListener?
    private var incoming: [NWConnection] = []

    func start() {
        statusText = AppCopy.wifiWaiting
        do {
            let listener = try NWListener(using: .tcp, on: 8080)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .ready = state {
                        self?.addressText = "http://\(Self.wifiAddress() ?? AppCopy.wifiThisDevice):8080/"
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            addressText = AppCopy.wifiStartFailed
            statusText = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        incoming.forEach { $0.cancel() }
        incoming.removeAll()
    }

    private func handle(_ conn: NWConnection) {
        incoming.append(conn)
        conn.start(queue: .main)
        receiveAll(conn, buffer: Data())
    }

    private func receiveAll(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 256) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                var buf = buffer
                if let data { buf.append(data) }
                if let error {
                    self.respond(conn, status: "500 Internal Server Error", body: Data(error.localizedDescription.utf8), contentType: "text/plain; charset=utf-8")
                    return
                }
                // ヘッダ完了まで待つ
                guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                    if isComplete {
                        self.respond(conn, status: "400 Bad Request", body: Data("incomplete".utf8), contentType: "text/plain")
                    } else {
                        self.receiveAll(conn, buffer: buf)
                    }
                    return
                }
                let headerData = buf.subdata(in: buf.startIndex..<headerEnd.lowerBound)
                let header = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStart = headerEnd.upperBound
                let contentLength = Self.contentLength(from: header) ?? 0

                if header.hasPrefix("GET / ") || header.contains("GET / HTTP") {
                    let html = AppCopy.wifiUploadPageHTML
                    self.respond(conn, status: "200 OK", body: Data(html.utf8), contentType: "text/html; charset=utf-8")
                    return
                }

                if header.hasPrefix("POST /upload") {
                    let have = buf.count - bodyStart
                    if have < contentLength && !isComplete {
                        self.receiveAll(conn, buffer: buf)
                        return
                    }
                    let body = buf.subdata(in: bodyStart..<buf.endIndex)
                    do {
                        let saved = try self.saveMultipart(body: body, header: header)
                        self.statusText = AppCopy.wifiReceived
                        self.lastSavedURL = saved
                        self.lastSavedName = saved.lastPathComponent
                        self.onFileReceived?(saved)
                        let ok = AppCopy.wifiReceivedHTML
                        self.respond(conn, status: "200 OK", body: Data(ok.utf8), contentType: "text/html; charset=utf-8")
                    } catch {
                        self.statusText = error.localizedDescription
                        self.respond(conn, status: "400 Bad Request", body: Data(error.localizedDescription.utf8), contentType: "text/plain; charset=utf-8")
                    }
                    return
                }

                self.respond(conn, status: "404 Not Found", body: Data("not found".utf8), contentType: "text/plain")
            }
        }
    }

    private func saveMultipart(body: Data, header: String) throws -> URL {
        guard let boundary = Self.boundary(from: header) else {
            throw NSError(domain: "WiFi", code: 1, userInfo: [NSLocalizedDescriptionKey: AppCopy.wifiNoBoundary])
        }
        let sep = Data("--\(boundary)".utf8)
        guard let first = body.range(of: sep) else {
            throw NSError(domain: "WiFi", code: 2, userInfo: [NSLocalizedDescriptionKey: AppCopy.wifiNoFilePart])
        }
        var search = first.upperBound
        // skip CRLF after boundary
        if body[search...].starts(with: Data("\r\n".utf8)) { search += 2 }
        guard let nextBound = body.range(of: sep, in: search..<body.endIndex) else {
            throw NSError(domain: "WiFi", code: 3, userInfo: [NSLocalizedDescriptionKey: AppCopy.wifiNoFileEnd])
        }
        let part = body.subdata(in: search..<nextBound.lowerBound)
        guard let partHeaderEnd = part.range(of: Data("\r\n\r\n".utf8)) else {
            throw NSError(domain: "WiFi", code: 4, userInfo: [NSLocalizedDescriptionKey: AppCopy.wifiBadPartHeader])
        }
        let partHeader = String(data: part.subdata(in: part.startIndex..<partHeaderEnd.lowerBound), encoding: .utf8) ?? ""
        var fileData = part.subdata(in: partHeaderEnd.upperBound..<part.endIndex)
        // trailing CRLF before next boundary
        if fileData.count >= 2, fileData.suffix(2) == Data("\r\n".utf8) {
            fileData = fileData.dropLast(2)
        }
        let name = Self.filename(from: partHeader) ?? "upload.bin"
        let dest = try ImportStaging.fileURL(named: name)
        try fileData.write(to: dest, options: .atomic)
        return dest
    }

    private func respond(_ conn: NWConnection, status: String, body: Data, contentType: String) {
        var header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func contentLength(from header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                return Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
            }
        }
        return nil
    }

    private static func boundary(from header: String) -> String? {
        for line in header.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-type:"), let r = line.range(of: "boundary=") {
                return String(line[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
        }
        return nil
    }

    private static func filename(from partHeader: String) -> String? {
        // filename="..."
        guard let r = partHeader.range(of: "filename=\"") else { return nil }
        let rest = partHeader[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let name = String(rest[..<end])
        return (name as NSString).lastPathComponent
    }

    private static func wifiAddress() -> String? {
        var addr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addr) == 0, let first = addr else { return nil }
        defer { freeifaddrs(addr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name == "en0" || name.hasPrefix("en") else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(p.pointee.ifa_addr, socklen_t(p.pointee.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }
}
