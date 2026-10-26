import Foundation

enum HTTPDownloadService {
    static func download(
        urlString: String,
        username: String = "",
        password: String = "",
        to local: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteError.invalidURL
        }
        var request = URLRequest(url: url)
        if !username.isEmpty {
            let raw = "\(username):\(password)"
            request.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("ダウンロードに失敗しました")
        }
        let expected = response.expectedContentLength
        var data = Data()
        if expected > 0 {
            data.reserveCapacity(Int(expected))
        }
        var received: Int64 = 0
        for try await byte in bytes {
            data.append(byte)
            received += 1
            if expected > 0, received % 32_768 == 0 {
                onProgress?(Double(received) / Double(expected))
            }
        }
        onProgress?(1)
        try? FileManager.default.removeItem(at: local)
        try data.write(to: local, options: .atomic)
    }
}
