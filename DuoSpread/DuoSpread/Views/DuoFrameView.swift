import SwiftUI

/// Device chrome that visualizes iPhone Duo open / closed / table poses.
struct DuoFrameView<Content: View>: View {
    let pose: DuoPose
    @ViewBuilder var content: () -> Content

    private var hingeWidth: CGFloat { pose == .open ? 14 : 0 }

    var body: some View {
        GeometryReader { geo in
            let radius: CGFloat = pose == .closed ? 36 : (pose == .table ? 24 : 28)
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.18, blue: 0.20),
                                Color(red: 0.08, green: 0.09, blue: 0.11)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 28, y: 18)

                content()
                    .clipShape(RoundedRectangle(cornerRadius: max(radius - 10, 12), style: .continuous))
                    .padding(pose == .closed ? 14 : 12)

                if pose == .open {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.55),
                                    Color(white: 0.22),
                                    Color(white: 0.38),
                                    Color(white: 0.22),
                                    Color.black.opacity(0.55)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: hingeWidth)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    private var aspect: CGFloat {
        switch pose {
        case .open: return 16 / 10
        case .closed: return 9 / 16
        case .table: return 10 / 14
        }
    }
}
