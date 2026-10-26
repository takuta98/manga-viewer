import SwiftUI

/// Duo の表示枠。実レイアウト判定は DisplayLayoutResolver が担う。
struct DuoFrameView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}
