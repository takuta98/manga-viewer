import SwiftUI

/// Duo 見開きの枠。中身のサイズを変えず、親から与えられた領域いっぱいに敷く。
/// （aspectRatio で自分の高さを変えると GeometryReader 計測ループの原因になる）
struct DuoFrameView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}
