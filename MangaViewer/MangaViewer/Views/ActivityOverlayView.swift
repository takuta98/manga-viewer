import SwiftUI

struct ActivityOverlayView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    var body: some View {
        if let banner = activity.banner {
            Text(banner)
                .font(.footnote.weight(.semibold))
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if activity.banner == banner { activity.banner = nil }
                    }
                }
        }
    }
}
