import SwiftUI
import UIKit

/// ページ画像1枚。ジェスチャは付けない（ページ送りは PageBrowser の管轄）。
struct PageImageView: View {
    let url: URL?
    let pageNumber: Int
    let fitMode: PageFitMode
    /// 見開きで綴じ目に触れる辺。指定すると画像をその辺に寄せて中央の隙間をなくす。
    var spineEdge: HorizontalEdge? = nil

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

    /// ページを枠に収める表示サイズ。fitWidth/Height はその軸いっぱい（はみ出す側は枠で切れる）。
    private func fittedSize(_ image: CGSize, in pane: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return pane }
        let scale: CGFloat = switch fitMode {
        case .fitWidth: pane.width / image.width
        case .fitHeight: pane.height / image.height
        default: min(pane.width / image.width, pane.height / image.height)
        }
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image {
                    let fit = fittedSize(image.size, in: geo.size)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        // 綴じ目側に寄せる（中央の隙間をなくす）
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: spineEdge == .leading
                                ? .leading
                                : (spineEdge == .trailing ? .trailing : .center)
                        )
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
