import SwiftUI

/// 転送・取込の状況を別画面で確認する。裏で動いているジョブもここに出す。
struct TransferStatusView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if activity.jobs.isEmpty {
                    ContentUnavailableView(
                        "転送はありません",
                        systemImage: "arrow.down.circle",
                        description: Text("NAS や URL からの取り込みは裏で進み、ここに表示されます。")
                    )
                } else {
                    if !activity.activeJobs.isEmpty {
                        Section("進行中") {
                            ForEach(activity.activeJobs) { job in
                                jobRow(job)
                            }
                        }
                    }
                    let finished = activity.jobs.filter(\.isFinished)
                    if !finished.isEmpty {
                        Section("完了 / 失敗") {
                            ForEach(finished) { job in
                                jobRow(job)
                            }
                        }
                    }
                }
            }
            .navigationTitle("転送状況")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("消去") {
                        activity.clearFinished()
                    }
                    .disabled(activity.jobs.allSatisfy { !$0.isFinished })
                }
            }
        }
    }

    @ViewBuilder
    private func jobRow(_ job: TransferActivityCenter.Job) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if !job.isFinished {
                    Button("中止") { activity.cancel(job.id) }
                        .font(.caption.weight(.semibold))
                }
            }
            Text(job.status)
                .font(.subheadline)
                .foregroundStyle(job.isFailed ? .red : .secondary)
            if let fraction = job.fraction {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else if !job.isFinished {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }
}
