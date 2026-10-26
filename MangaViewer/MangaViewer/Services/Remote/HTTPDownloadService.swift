import Foundation

enum HTTPDownloadService {
    static func download(urlString: String, username: String = "", password: String = "", to local: URL) async throws {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteError.invalidURL
        }
        var request = URLRequest(url: url)
        if !username.isEmpty {
            let raw = "\(username):\(password)"
            request.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("ダウンロードに失敗しました")
        }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: temp, to: local)
    }
}
