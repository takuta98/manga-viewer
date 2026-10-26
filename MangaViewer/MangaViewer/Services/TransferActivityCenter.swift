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
        var volumeId: UUID?
    }

    @Published private(set) var jobs: [Job] = []
    @Published var toast: String?
    @Published var pendingOpenVolumeId: UUID?
    private var cancelFlags: [UUID: Bool] = [:]
    private var taskHandles: [UUID: Task<Void, Never>] = [:]
    private var toastToken = UUID()
    private var suppressCancelToast = false

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
                isCancelled: false,
                volumeId: nil
            ),
            at: 0
        )
        Self.requestNotificationPermissionOnce()
        if announce {
            if activeCount == 1 {
                showToast("\(AppCopy.downloadStarted)：\(title)", duration: 1.6)
            } else {
                showToast(AppCopy.downloadStarted, duration: 1.4)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        return id
    }

    func attachTask(_ id: UUID, _ task: Task<Void, Never>) { taskHandles[id] = task }
    func isCancelled(_ id: UUID) -> Bool { cancelFlags[id] == true }

    func cancel(_ id: UUID, announce: Bool = true) {
        cancelFlags[id] = true
        taskHandles[id]?.cancel()
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        if !jobs[idx].isFinished {
            jobs[idx].status = AppCopy.cancelling
            jobs[idx].isCancelled = true
            if announce {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    func cancelAllActive() {
        let ids = activeJobs.map(\.id)
        guard !ids.isEmpty else { return }
        suppressCancelToast = true
        for id in ids { cancel(id, announce: false) }
        showToast(AppCopy.cancelled, duration: 1.6)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            suppressCancelToast = false
        }
    }

    func update(_ id: UUID, status: String, fraction: Double? = nil) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = status
        if let fraction {
            jobs[idx].fraction = min(max(fraction, 0), 1)
        }
    }

    func succeed(_ id: UUID, message: String? = nil, volumeId: UUID? = nil) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        let title = jobs[idx].title
        jobs[idx].status = message ?? AppCopy.done
        jobs[idx].fraction = 1
        jobs[idx].isFinished = true
        if let volumeId { jobs[idx].volumeId = volumeId }
        taskHandles[id] = nil
        cancelFlags[id] = nil
        if let message {
            // 既存スキップ等でも volumeId があれば読む導線を添える
            if volumeId != nil {
                showToast("\(message) · \(AppCopy.readNow)", duration: 2.2)
            } else {
                showToast(message, duration: 2.0)
            }
        } else if volumeId != nil {
            showToast(AppCopy.downloadFinishedReadHint, duration: 2.2)
        } else {
            showToast("\(AppCopy.downloadFinished)：\(title)", duration: 2.0)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func fail(_ id: UUID, message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = message
        jobs[idx].isFailed = true
        jobs[idx].isFinished = true
        taskHandles[id] = nil
        cancelFlags[id] = nil
        showToast("\(AppCopy.downloadFailed)：\(message)", duration: 2.2)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func finishCancelled(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = AppCopy.cancelled
        jobs[idx].isCancelled = true
        jobs[idx].isFailed = false
        jobs[idx].isFinished = true
        taskHandles[id] = nil
        cancelFlags[id] = nil
        // 一括中止時は cancelAllActive 側で一度だけ通知する
        if !suppressCancelToast {
            showToast(AppCopy.cancelled, duration: 1.6)
        }
    }

    func clearFinished() {
        let finishedIds = jobs.filter(\.isFinished).map(\.id)
        jobs.removeAll { $0.isFinished }
        for id in finishedIds {
            taskHandles[id] = nil
            cancelFlags[id] = nil
        }
    }

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
