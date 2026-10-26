import Foundation
import Combine
import UIKit
import UserNotifications

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
    private var cancelFlags: [UUID: Bool] = [:]
    private var taskHandles: [UUID: Task<Void, Never>] = [:]

    var activeJobs: [Job] { jobs.filter { !$0.isFinished } }
    var activeCount: Int { activeJobs.count }

    static func requestNotificationPermissionOnce() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    @discardableResult
    func begin(title: String, status: String = "準備中…") -> UUID {
        let id = UUID()
        cancelFlags[id] = false
        jobs.insert(Job(id: id, title: title, status: status, fraction: nil, isFailed: false, isFinished: false, isCancelled: false), at: 0)
        return id
    }

    func attachTask(_ id: UUID, _ task: Task<Void, Never>) { taskHandles[id] = task }
    func isCancelled(_ id: UUID) -> Bool { cancelFlags[id] == true }

    func cancel(_ id: UUID) {
        cancelFlags[id] = true
        taskHandles[id]?.cancel()
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        if !jobs[idx].isFinished {
            jobs[idx].status = "キャンセル中…"
            jobs[idx].isCancelled = true
        }
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
        taskHandles[id] = nil
        banner = message
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let content = UNMutableNotificationContent()
        content.title = "取り込み完了"
        content.body = message
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func fail(_ id: UUID, message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = message
        jobs[idx].isFailed = true
        jobs[idx].isFinished = true
        taskHandles[id] = nil
        banner = message
    }

    func clearFinished() {
        jobs.removeAll { $0.isFinished }
    }
}
