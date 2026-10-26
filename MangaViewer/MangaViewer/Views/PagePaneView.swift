import SwiftUI
import UIKit

struct PagePaneView: View {
    let url: URL?
    let pageNumber: Int
    let fitMode: PageFitMode
    /// 縦スクロール用：幅に合わせて自然な高さを取る。
    var intrinsicHeight: Bool = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private var image: UIImage? {
        url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private var aspect: CGFloat {
        guard let image, image.size.height > 0 else { return 2.0 / 3.0 }
        return image.size.width / image.size.height
    }

    var body: some View {
        Group {
            if intrinsicHeight {
                zoomableImage(maxWidth: nil, maxHeight: nil)
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geo in
                    zoomableImage(
                        maxWidth: fitMode == .fitHeight ? nil : geo.size.width,
                        maxHeight: fitMode == .fitWidth ? nil : geo.size.height
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .background(Color.black)
        .clipped()
    }

    @ViewBuilder
    private func zoomableImage(maxWidth: CGFloat?, maxHeight: CGFloat?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(baseScale * value, 1), 4)
                            }
                            .onEnded { _ in
                                baseScale = scale
                                if scale < 1.05 {
                                    withAnimation {
                                        scale = 1; baseScale = 1
                                        offset = .zero; baseOffset = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.05 else { return }
                                offset = CGSize(
                                    width: baseOffset.width + value.translation.width,
                                    height: baseOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                baseOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1.05 {
                            scale = 1; baseScale = 1
                            offset = .zero; baseOffset = .zero
                        } else {
                            scale = 2.2; baseScale = 2.2
                        }
                    }
                }
                .accessibilityLabel("\(pageNumber) \(AppCopy.pageCountSuffix)")
                .accessibilityAddTraits(.isImage)
        } else {
            Color.black.overlay(
                Text("\(pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            )
        }
    }
}
