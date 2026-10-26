import Foundation
import Combine

@MainActor
final class TransferActivityCenter: ObservableObject {
    static let shared = TransferActivityCenter()

    struct Job: Identifiable, Equatable {
        let id: UUID
        var title: String
        var status: String
        var fraction: Double?
        var isFailed: Bool
        var isFinished: Bool
        var isCancelled: Bool
    }

    @Published private(set) var jobs: [Job] = []
    @Published var banner: String?
    private var bannerToken = UUID()
    private var cancelFlags: [UUID: Bool] = [:]

    var activeJobs: [Job] { jobs.filter { !$0.isFinished } }

    @discardableResult
    func begin(title: String, status: String = "準備中…") -> UUID {
        let id = UUID()
        cancelFlags[id] = false
        jobs.insert(
            Job(id: id, title: title, status: status, fraction: nil, isFailed: false, isFinished: false, isCancelled: false),
            at: 0
        )
        return id
    }

    func isCancelled(_ id: UUID) -> Bool {
        cancelFlags[id] == true
    }

    func cancel(_ id: UUID) {
        cancelFlags[id] = true
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = "キャンセル中…"
        jobs[idx].isCancelled = true
    }

    func update(_ id: UUID, status: String, fraction: Double? = nil) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = status
        if let fraction {
            let clamped = min(max(fraction, 0), 1)
            if let current = jobs[idx].fraction {
                jobs[idx].fraction = max(current, clamped)
            } else {
                jobs[idx].fraction = clamped
            }
        }
    }

    func succeed(_ id: UUID, banner message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = "完了"
        jobs[idx].fraction = 1
        jobs[idx].isFinished = true
        showBanner(message)
        scheduleCleanup(id)
        cancelFlags[id] = nil
    }

    func fail(_ id: UUID, message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = message
        jobs[idx].isFailed = true
        jobs[idx].isFinished = true
        showBanner(message)
        scheduleCleanup(id)
        cancelFlags[id] = nil
    }

    private func showBanner(_ message: String) {
        let token = UUID()
        bannerToken = token
        banner = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if bannerToken == token {
                banner = nil
            }
        }
    }

    private func scheduleCleanup(_ id: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            jobs.removeAll { $0.id == id }
        }
    }
}
