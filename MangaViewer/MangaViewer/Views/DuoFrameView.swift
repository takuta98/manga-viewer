import SwiftUI

/// ページを敷く枠。親から与えられた範囲をそのまま埋めるだけ。
struct DuoFrameView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            // ページは端まで敷く（カメラやホームバーの分だけ余白が入るのを防ぐ）
            .ignoresSafeArea()
    }
}
