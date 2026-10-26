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
        var sourceKey: String?
        var isFailed: Bool
        var isFinished: Bool
        var isCancelled: Bool
    }

    @Published private(set) var jobs: [Job] = []
    @Published var toast: String?
    private var cancelFlags: [UUID: Bool] = [:]
    private var taskHandles: [UUID: Task<Void, Never>] = [:]
    private var toastToken = UUID()

    var activeJobs: [Job] { jobs.filter { !$0.isFinished } }
    var activeCount: Int { activeJobs.count }

    func isActive(sourceKey: String) -> Bool {
        activeJobs.contains { $0.sourceKey == sourceKey }
    }

    static func requestNotificationPermissionOnce() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    @discardableResult
    func begin(
        title: String,
        status: String = AppCopy.downloadingItem,
        sourceKey: String? = nil,
        announce: Bool = true
    ) -> UUID {
        let id = UUID()
        cancelFlags[id] = false
        jobs.insert(
            Job(
                id: id,
                title: title,
                status: status,
                fraction: nil,
                sourceKey: sourceKey,
                isFailed: false,
                isFinished: false,
                isCancelled: false
            ),
            at: 0
        )
        if announce {
            if activeCount == 1 {
                showToast("\(AppCopy.downloadStarted)\n\(title)", duration: 1.6)
            } else {
                showToast(AppCopy.downloadStarted, duration: 1.6)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        return id
    }

    func attachTask(_ id: UUID, _ task: Task<Void, Never>) { taskHandles[id] = task }
    func isCancelled(_ id: UUID) -> Bool { cancelFlags[id] == true }

    func cancel(_ id: UUID) {
        cancelFlags[id] = true
        taskHandles[id]?.cancel()
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        if !jobs[idx].isFinished {
            jobs[idx].status = AppCopy.cancelling
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

    func succeed(_ id: UUID, message: String? = nil) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        let title = jobs[idx].title
        jobs[idx].status = AppCopy.done
        jobs[idx].fraction = 1
        jobs[idx].isFinished = true
        taskHandles[id] = nil
        let body = message ?? "\(AppCopy.downloadFinished)\n\(title)"
        showToast(body, duration: 2.2)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let content = UNMutableNotificationContent()
        content.title = AppCopy.downloadFinished
        content.body = title
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    func fail(_ id: UUID, message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = message
        jobs[idx].isFailed = true
        jobs[idx].isFinished = true
        taskHandles[id] = nil
        showToast("\(AppCopy.downloadFailed)\n\(message)", duration: 2.2)
    }

    func clearFinished() { jobs.removeAll { $0.isFinished } }

    func showToast(_ message: String, duration: Double = 2.0) {
        let token = UUID()
        toastToken = token
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if toastToken == token { toast = nil }
        }
    }
}
