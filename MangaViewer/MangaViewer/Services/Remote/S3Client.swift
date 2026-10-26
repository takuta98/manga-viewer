import Foundation
import CryptoKit

enum S3Client {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let prefix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var comp = URLComponents(string: endpoint(source))!
        comp.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: prefix.isEmpty ? "" : prefix + "/"),
            URLQueryItem(name: "delimiter", value: "/"),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        try sign(&req, source: source, payloadHash: emptyHash)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("S3の一覧取得に失敗しました")
        }
        return parseList(data, prefix: prefix)
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        let key = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: endpoint(source) + "/" + key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        try sign(&req, source: source, payloadHash: emptyHash)
        let (tmp, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("S3のダウンロードに失敗しました")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    private static var emptyHash: String {
        SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
    }

    private static func endpoint(_ source: RemoteSource) -> String {
        let scheme = source.useTLS ? "https" : "http"
        if source.host.contains(".") {
            return "\(scheme)://\(source.host)/\(source.bucket)"
        }
        return "\(scheme)://\(source.bucket).s3.\(source.region).amazonaws.com"
    }

    private static func parseList(_ data: Data, prefix: String) -> [RemoteEntry] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var entries: [RemoteEntry] = []
        for p in text.components(separatedBy: "<Prefix>").dropFirst() {
            guard let end = p.range(of: "</Prefix>") else { continue }
            let full = String(p[..<end.lowerBound])
            let name = full.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").last ?? full
            if name.isEmpty { continue }
            entries.append(RemoteEntry(name: name, path: full.trimmingCharacters(in: CharacterSet(charactersIn: "/")), isDirectory: true, size: nil))
        }
        for p in text.components(separatedBy: "<Key>").dropFirst() {
            guard let end = p.range(of: "</Key>") else { continue }
            let key = String(p[..<end.lowerBound])
            if key.hasSuffix("/") { continue }
            let name = (key as NSString).lastPathComponent
            entries.append(RemoteEntry(name: name, path: key, isDirectory: false, size: nil))
        }
        return entries
    }

    private static func sign(_ req: inout URLRequest, source: RemoteSource, payloadHash: String) throws {
        let method = req.httpMethod ?? "GET"
        guard let url = req.url else { throw RemoteError.message("S3のURLが不正です") }
        let amzDate = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let short = String(amzDate.prefix(8))
        req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        req.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        req.setValue(url.host, forHTTPHeaderField: "host")
        let canonicalHeaders = "host:\(url.host!)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonical = "\(method)\n\(url.path)\n\(url.query ?? "")\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalHash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        let scope = "\(short)/\(source.region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(canonicalHash)"
        let kDate = hmac("AWS4\(source.password)", short)
        let kRegion = hmac(kDate, source.region)
        let kService = hmac(kRegion, "s3")
        let kSigning = hmac(kService, "aws4_request")
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: kSigning))
            .map { String(format: "%02x", $0) }.joined()
        let auth = "AWS4-HMAC-SHA256 Credential=\(source.username)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        req.setValue(auth, forHTTPHeaderField: "Authorization")
    }

    private static func hmac(_ key: String, _ data: String) -> Data {
        hmac(Data(key.utf8), data)
    }
    private static func hmac(_ key: Data, _ data: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key)))
    }
}
