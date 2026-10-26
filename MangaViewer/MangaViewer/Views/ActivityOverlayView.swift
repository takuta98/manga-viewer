import SwiftUI

struct ActivityOverlayView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared

    var body: some View {
        VStack {
            if let toast = activity.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: activity.toast)
        .allowsHitTesting(false)
    }
}

struct DownloadStatusChip: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    var onTap: () -> Void

    var body: some View {
        if activity.activeCount > 0 {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(AppCopy.downloadActive) \(activity.activeCount)件")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
