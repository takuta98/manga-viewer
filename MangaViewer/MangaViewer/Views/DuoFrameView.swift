import SwiftUI

/// iPhone Duo の見開き枠。横向きで画面いっぱいに2ページを並べる。
struct DuoFrameView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}
