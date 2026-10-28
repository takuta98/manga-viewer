import SwiftUI
import UIKit

/// ページ画像1枚。ジェスチャは付けない（ページ送りは PageBrowser の管轄）。
struct PageImageView: View {
    let url: URL?
    let pageNumber: Int
    let fitMode: PageFitMode

    private var image: UIImage? {
        guard let url else { return nil }
        if let fromDisk = UIImage(contentsOfFile: url.path) { return fromDisk }
        let base = url.deletingPathExtension().lastPathComponent
        if let named = UIImage(named: base) { return named }
        if let bundled = Bundle.main.url(
            forResource: base,
            withExtension: "png",
            subdirectory: "SampleManga/sample"
        ) {
            return UIImage(contentsOfFile: bundled.path)
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: fitMode == .fitHeight ? nil : geo.size.width,
                            maxHeight: fitMode == .fitWidth ? nil : geo.size.height
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Text("\(pageNumber)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .background(Color.black)
        .accessibilityLabel("\(pageNumber) ページ")
        .accessibilityAddTraits(.isImage)
    }
}
