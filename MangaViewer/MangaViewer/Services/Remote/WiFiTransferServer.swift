import Foundation
import Network

/// Simple HTTP upload server for LAN Wi-Fi transfer (browser POST multipart).
@MainActor
final class WiFiTransferServer: ObservableObject {
    static let shared = WiFiTransferServer()

    @Published private(set) var isRunning = false
    @Published private(set) var addressText = ""
    @Published var lastError: String?

    private var listener: NWListener?
    var onFileReceived: ((URL) -> Void)?

    func start(port: UInt16 = 8080) {
        stop()
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.addressText = self?.lanURL(port: port) ?? "http://\(port)"
                    case .failed(let err):
                        self?.lastError = err.localizedDescription
                        self?.isRunning = false
                    default: break
                    }
                }
            }
            listener?.start(queue: .global())
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func lanURL(port: UInt16) -> String {
        let ip = Self.wifiAddress() ?? "本機IP"
        return "http://\(ip):\(port)"
    }

    private static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    nonisolated private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        receiveHeader(connection, buffer: Data())
    }

    nonisolated private func receiveHeader(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, _, error in
            guard error == nil, let content else {
                connection.cancel()
                return
            }
            var buf = buffer
            buf.append(content)
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: 0..<range.lowerBound)
                let header = String(data: headerData, encoding: .utf8) ?? ""
                let rest = buf.subdata(in: range.upperBound..<buf.count)
                if header.hasPrefix("GET") {
                    self?.respondHTML(connection)
                } else if header.hasPrefix("POST") {
                    let length = Self.contentLength(header) ?? 0
                    self?.receiveBody(connection, remaining: length - rest.count, collected: rest)
                } else {
                    self?.respond(connection, status: "400 Bad Request", body: Data("bad request".utf8))
                }
            } else {
                self?.receiveHeader(connection, buffer: buf)
            }
        }
    }

    nonisolated private func receiveBody(_ connection: NWConnection, remaining: Int, collected: Data) {
        if remaining <= 0 {
            finishUpload(connection, body: collected)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: max(remaining, 1)) { [weak self] content, _, _, _ in
            var data = collected
            if let content { data.append(content) }
            let left = remaining - (content?.count ?? 0)
            self?.receiveBody(connection, remaining: left, collected: data)
        }
    }

    nonisolated private func finishUpload(_ connection: NWConnection, body: Data) {
        // Extremely small multipart parser: find filename and binary after headers.
        if let fileURL = Self.saveMultipart(body) {
            Task { @MainActor in
                self.onFileReceived?(fileURL)
            }
            respond(connection, status: "200 OK", body: Data("OK uploaded".utf8))
        } else {
            respond(connection, status: "400 Bad Request", body: Data("upload parse failed".utf8))
        }
    }

    nonisolated private func respondHTML(_ connection: NWConnection) {
        let html = """
        <html><body style="font-family:sans-serif;padding:24px">
        <h1>manga viewer Wi-Fi Transfer</h1>
        <form method="POST" enctype="multipart/form-data">
        <input type="file" name="file" multiple/>
        <button type="submit">Upload</button>
        </form></body></html>
        """
        respond(connection, status: "200 OK", body: Data(html.utf8), contentType: "text/html; charset=utf-8")
    }

    nonisolated private func respond(_ connection: NWConnection, status: String, body: Data, contentType: String = "text/plain") {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    nonisolated private static func contentLength(_ header: String) -> Int? {
        for line in header.split(whereSeparator: \.isNewline) {
            let l = line.lowercased()
            if l.hasPrefix("content-length:") {
                return Int(l.split(separator: ":")[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    nonisolated private static func saveMultipart(_ body: Data) -> URL? {
        guard let textProbe = String(data: body.prefix(2048), encoding: .utf8) else { return nil }
        guard let nameRange = textProbe.range(of: "filename=\"") else { return nil }
        let after = textProbe[nameRange.upperBound...]
        guard let endQuote = after.firstIndex(of: "\"") else { return nil }
        let filename = String(after[..<endQuote])
        guard let sep = body.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        // Find next boundary near end: last \r\n--
        var payload = body.subdata(in: sep.upperBound..<body.endIndex)
        if let boundaryEnd = payload.range(of: Data("\r\n--".utf8), options: .backwards) {
            payload = payload.subdata(in: 0..<boundaryEnd.lowerBound)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wifi-upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(filename.isEmpty ? "upload.bin" : filename)
        try? payload.write(to: out)
        return out
    }
}
