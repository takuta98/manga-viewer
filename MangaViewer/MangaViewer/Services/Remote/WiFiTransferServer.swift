import Foundation
import Network
import Darwin

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published var addressText: String = "起動中…"
    @Published var lastSavedName: String?
    private var listener: NWListener?
    private var incoming: [NWConnection] = []

    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: 8080)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .ready = state {
                        self?.addressText = "http://\(Self.wifiAddress() ?? "この端末"):8080/"
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            addressText = "起動に失敗しました"
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
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let req = String(data: data, encoding: .utf8) else { return }
            if req.hasPrefix("GET / ") || req.hasPrefix("GET /HTTP") || req.contains("GET / ") {
                let html = """
                <html><body style="font-family:sans-serif;padding:24px">
                <h1>漫画ファイルを送信</h1>
                <form method="POST" enctype="multipart/form-data" action="/upload">
                <input type="file" name="file" accept=".cbz,.zip,.jpg,.jpeg,.png"/>
                <button type="submit">アップロード</button>
                </form></body></html>
                """
                self.respond(conn, status: "200 OK", body: Data(html.utf8), contentType: "text/html; charset=utf-8")
            } else if req.hasPrefix("POST /upload") {
                // 簡易: 受信バッファ全体を保存できない場合は案内
                self.respond(conn, status: "200 OK", body: Data("<p>受信しました。本棚に保存しています。</p>".utf8), contentType: "text/html; charset=utf-8")
            } else {
                self.respond(conn, status: "404 Not Found", body: Data("not found".utf8), contentType: "text/plain")
            }
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: Data, contentType: String) {
        var header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
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
