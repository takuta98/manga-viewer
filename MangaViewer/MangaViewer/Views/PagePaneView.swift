import SwiftUI
import UIKit

struct PagePaneView: View {
    let url: URL?
    let pageNumber: Int?
    var fitMode: PageFitMode = .fitScreen

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image {
                    let fitted = fittedSize(imageSize: image.size, in: geo.size)
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fitted.width, height: fitted.height)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                    .disabled(fitMode == .fitScreen)
                    .accessibilityLabel(pageNumber.map { "ページ \($0)" } ?? "ページ")
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("読み込めません")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: "\(url?.path ?? "")-\(fitMode.rawValue)") {
            await load()
        }
    }

    private func fittedSize(imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let imageRatio = imageSize.width / imageSize.height
        switch fitMode {
        case .fitWidth:
            let w = bounds.width
            return CGSize(width: w, height: w / imageRatio)
        case .fitHeight:
            let h = bounds.height
            return CGSize(width: h * imageRatio, height: h)
        case .fitScreen:
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }
    }

    private func load() async {
        failed = false
        image = nil
        guard let url else {
            failed = true
            return
        }
        if let cached = PageImageCache.shared.image(for: url) {
            image = cached
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) {
            SampleImage.uiImage(url: url)
        }.value
        if let loaded {
            PageImageCache.shared.store(loaded, for: url)
            image = loaded
        } else {
            failed = true
        }
    }
}

final class PageImageCache {
    static let shared = PageImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 64
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.path as NSString)
    }

    func prefetch(urls: [URL]) {
        for url in urls {
            if image(for: url) != nil { continue }
            Task.detached(priority: .utility) {
                if let img = SampleImage.uiImage(url: url) {
                    await MainActor.run {
                        PageImageCache.shared.store(img, for: url)
                    }
                }
            }
        }
    }
}

enum SampleImage {
    static func uiImage(url: URL) -> UIImage? {
        if let ui = UIImage(contentsOfFile: url.path) {
            return ui
        }
        let name = url.deletingPathExtension().lastPathComponent
        if let ui = UIImage(named: name) {
            return ui
        }
        if let bundled = Bundle.main.url(
            forResource: name,
            withExtension: url.pathExtension.isEmpty ? "png" : url.pathExtension,
            subdirectory: "SampleManga/sample"
        ) {
            return UIImage(contentsOfFile: bundled.path)
        }
        return nil
    }

    static func load(url: URL) -> Image? {
        uiImage(url: url).map { Image(uiImage: $0) }
    }

    static func load(named name: String) -> Image? {
        if let ui = UIImage(named: name) {
            return Image(uiImage: ui)
        }
        for subdirectory in ["SampleManga/sample", "sample", nil as String?] {
            let url: URL?
            if let subdirectory {
                url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
            } else {
                url = Bundle.main.url(forResource: name, withExtension: "png")
            }
            if let url, let ui = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: ui)
            }
        }
        return nil
    }
}
