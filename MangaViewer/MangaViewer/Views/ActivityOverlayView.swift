import SwiftUI

struct ActivityOverlayView: View {
    @ObservedObject var activity = TransferActivityCenter.shared
    var showsCancel: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            if let banner = activity.banner {
                Text(banner)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.82), in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ForEach(activity.activeJobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(job.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        if showsCancel, !job.isFinished {
                            Button("中止") {
                                activity.cancel(job.id)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        if let fraction = job.fraction {
                            Text("\(Int(fraction * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(job.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let fraction = job.fraction {
                        ProgressView(value: fraction)
                    }
                }
                .padding(14)
                .frame(maxWidth: 420)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.25), value: activity.activeJobs.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: activity.banner)
    }
}
