import Foundation
import CryptoKit

/// S3-compatible LIST/GET (AWS SigV4) for MinIO / Wasabi / AWS.
enum S3Client {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let bucket = source.bucket?.isEmpty == false ? source.bucket! : source.shareOrPath
        guard !bucket.isEmpty else { throw RemoteError.notConfigured }
        let prefix = path.isEmpty ? "" : (path.hasSuffix("/") ? path : path + "/")
        var comps = try endpointComponents(source)
        comps.path = "/"
        comps.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: prefix),
            URLQueryItem(name: "delimiter", value: "/")
        ]
        guard let url = comps.url else { throw RemoteError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try sign(&request, source: source, bucket: bucket, canonicalURI: "/")
        // Path-style: host/bucket
        if !(comps.host?.contains(bucket) ?? false) {
            comps.path = "/\(bucket)"
            request.url = comps.url
            try sign(&request, source: source, bucket: bucket, canonicalURI: "/\(bucket)")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RemoteError.requestFailed("S3 LIST failed: \(body.prefix(200))")
        }
        return parseList(xml: String(data: data, encoding: .utf8) ?? "", prefix: prefix)
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let bucket = source.bucket?.isEmpty == false ? source.bucket! : source.shareOrPath
        var comps = try endpointComponents(source)
        comps.path = "/\(bucket)/\(path)"
        comps.query = nil
        guard let url = comps.url else { throw RemoteError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try sign(&request, source: source, bucket: bucket, canonicalURI: "/\(bucket)/\(path)")
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("S3 GET failed")
        }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: temp, to: local)
    }

    private static func endpointComponents(_ source: RemoteSource) throws -> URLComponents {
        var host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.contains("://") {
            host = (source.useTLS ? "https://" : "http://") + host
        }
        guard var comps = URLComponents(string: host) else { throw RemoteError.invalidURL }
        if let port = source.port { comps.port = port }
        return comps
    }

    private static func parseList(xml: String, prefix: String) -> [RemoteEntry] {
        var entries: [RemoteEntry] = []
        // Common prefixes (folders)
        for folder in tags(xml, "Prefix") {
            if folder == prefix || folder.isEmpty { continue }
            let name = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/").last.map(String.init) ?? folder
            entries.append(RemoteEntry(name: name, path: folder, isDirectory: true, size: nil, downloadURL: nil))
        }
        // Contents
        let chunks = xml.components(separatedBy: "<Contents>").dropFirst()
        for chunk in chunks {
            guard let key = tag(chunk, "Key"), key != prefix else { continue }
            if key.hasSuffix("/") { continue }
            let name = key.split(separator: "/").last.map(String.init) ?? key
            let size = tag(chunk, "Size").flatMap { Int64($0) }
            entries.append(RemoteEntry(name: name, path: key, isDirectory: false, size: size, downloadURL: nil))
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func tags(_ xml: String, _ name: String) -> [String] {
        var result: [String] = []
        var search = xml[...]
        let open = "<\(name)>"
        let close = "</\(name)>"
        while let s = search.range(of: open) {
            search = search[s.upperBound...]
            guard let e = search.range(of: close) else { break }
            result.append(String(search[..<e.lowerBound]))
            search = search[e.upperBound...]
        }
        return result
    }

    private static func tag(_ text: String, _ name: String) -> String? {
        tags(text, name).first
    }

    private static func sign(_ request: inout URLRequest, source: RemoteSource, bucket: String, canonicalURI: String) throws {
        let access = source.username
        let secret = source.password
        guard !access.isEmpty, !secret.isEmpty else { throw RemoteError.notConfigured }
        let region = source.region?.isEmpty == false ? source.region! : "us-east-1"
        let now = Date()
        let amzDate = Self.amzDate(now)
        let dateStamp = String(amzDate.prefix(8))
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        guard let url = request.url, let host = url.host else { throw RemoteError.invalidURL }
        request.setValue(host, forHTTPHeaderField: "host")

        let method = request.httpMethod ?? "GET"
        let query = url.query ?? ""
        let canonicalQuery = query.split(separator: "&").map(String.init).sorted().joined(separator: "&")
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:UNSIGNED-PAYLOAD\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let signingKey = awsSignKey(secret: secret, dateStamp: dateStamp, region: region, service: "s3")
        let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))
        let auth = "AWS4-HMAC-SHA256 Credential=\(access)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        _ = bucket
    }

    private static func amzDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(key: Data, data: Data) -> Data {
        let keySym = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: keySym))
    }

    private static func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func awsSignKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secret)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }
}
