import Foundation
import Combine

/// ダウンロード／取り込みの進捗をアプリ全体で共有する。
@MainActor
final class TransferActivityCenter: ObservableObject {
    static let shared = TransferActivityCenter()

    struct Job: Identifiable, Equatable {
        let id: UUID
        var title: String
        var status: String
        /// `nil` は不定進捗（スピナー）。
        var fraction: Double?
        var isFailed: Bool
        var isFinished: Bool
    }

    @Published private(set) var jobs: [Job] = []
    @Published var banner: String?

    var activeJobs: [Job] { jobs.filter { !$0.isFinished } }

    @discardableResult
    func begin(title: String, status: String = "準備中…") -> UUID {
        let id = UUID()
        jobs.insert(
            Job(id: id, title: title, status: status, fraction: nil, isFailed: false, isFinished: false),
            at: 0
        )
        return id
    }

    func update(_ id: UUID, status: String, fraction: Double? = nil) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = status
        if let fraction {
            jobs[idx].fraction = min(max(fraction, 0), 1)
        }
    }

    func succeed(_ id: UUID, banner message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = "完了"
        jobs[idx].fraction = 1
        jobs[idx].isFinished = true
        banner = message
        scheduleCleanup(id)
        clearBannerLater()
    }

    func fail(_ id: UUID, message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = message
        jobs[idx].isFailed = true
        jobs[idx].isFinished = true
        banner = message
        scheduleCleanup(id)
        clearBannerLater()
    }

    private func scheduleCleanup(_ id: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            jobs.removeAll { $0.id == id }
        }
    }

    private func clearBannerLater() {
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            banner = nil
        }
    }
}
