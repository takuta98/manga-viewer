import SwiftUI

struct TransferStatusView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if activity.jobs.isEmpty {
                    ContentUnavailableView("転送はありません", systemImage: "arrow.down.circle",
                                           description: Text("取り込みは裏で進み、ここに表示されます。"))
                } else {
                    ForEach(activity.jobs) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(job.title).font(.headline).lineLimit(2)
                                Spacer()
                                if !job.isFinished {
                                    Button("中止") { activity.cancel(job.id) }.font(.caption.weight(.semibold))
                                }
                            }
                            Text(job.status).font(.subheadline).foregroundStyle(job.isFailed ? .red : .secondary)
                            if let f = job.fraction { ProgressView(value: f) }
                            else if !job.isFinished { ProgressView() }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("転送状況")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("消去") { activity.clearFinished() }
                        .disabled(activity.jobs.allSatisfy { !$0.isFinished })
                }
            }
        }
    }
}
