import SwiftUI

struct TransferStatusView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if activity.jobs.isEmpty {
                    ContentUnavailableView(
                        AppCopy.downloadEmptyTitle,
                        systemImage: "arrow.down.circle",
                        description: Text(AppCopy.downloadEmptyBody)
                    )
                } else {
                    List {
                        ForEach(activity.jobs) { job in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(job.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    if !job.isFinished {
                                        Button(AppCopy.cancelDownload) { activity.cancel(job.id) }
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                Text(job.status)
                                    .font(.subheadline)
                                    .foregroundStyle(job.isFailed ? .red : .secondary)
                                if let f = job.fraction {
                                    ProgressView(value: f)
                                } else if !job.isFinished {
                                    ProgressView()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(AppCopy.downloads)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppCopy.clearFinished) { activity.clearFinished() }
                        .disabled(!activity.jobs.contains(where: \.isFinished))
                }
            }
        }
    }
}
