import SwiftUI

/// Duo / 横向き向けの見開き枠。中身を画面いっぱいに広げる。
struct DuoFrameView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}
