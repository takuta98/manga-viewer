import Foundation
import Combine
import UIKit
import UserNotifications

@MainActor
final class TransferActivityCenter: ObservableObject {
    static let shared = TransferActivityCenter()

    /// 書庫表示時に一度だけ通知許可を求める（未決定のときだけシステムダイアログ）。
    static func requestNotificationPermissionOnce() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    struct Job: Identifiable, Equatable {
        let id: UUID
        var title: String
        var status: String
        var fraction: Double?
        var isFailed: Bool
        var isFinished: Bool
        var isCancelled: Bool
        var finishedAt: Date?
    }

    @Published private(set) var jobs: [Job] = []
    @Published var banner: String?
    private var bannerToken = UUID()
    private var cancelFlags: [UUID: Bool] = [:]
    private var taskHandles: [UUID: Task<Void, Never>] = [:]

    /// 完了ジョブを自動削除するまでの保持時間（それ以前は clearFinished まで残す）。
    private static let finishedRetention: TimeInterval = 24 * 60 * 60

    var activeJobs: [Job] { jobs.filter { !$0.isFinished } }

    var activeCount: Int { activeJobs.count }

    @discardableResult
    func begin(title: String, status: String = "準備中…") -> UUID {
        let id = UUID()
        cancelFlags[id] = false
        jobs.insert(
            Job(
                id: id,
                title: title,
                status: status,
                fraction: nil,
                isFailed: false,
                isFinished: false,
                isCancelled: false,
                finishedAt: nil
            ),
            at: 0
        )
        return id
    }

    /// 裏で動かす Task を登録。cancel() 時に Task.cancel() する。
    func attachTask(_ id: UUID, _ task: Task<Void, Never>) {
        taskHandles[id] = task
    }

    func isCancelled(_ id: UUID) -> Bool {
        cancelFlags[id] == true
    }

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
        let jobTitle = jobs[idx].title
        jobs[idx].status = "完了"
        jobs[idx].fraction = 1
        jobs[idx].isFinished = true
        jobs[idx].finishedAt = Date()
        taskHandles[id] = nil
        cancelFlags[id] = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showBanner(message)
        postImportCompletedNotification(jobTitle: jobTitle, body: message)
        scheduleRetentionCleanup(id)
    }

    func fail(_ id: UUID, message: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].status = message
        jobs[idx].isFailed = true
        jobs[idx].isFinished = true
        jobs[idx].finishedAt = Date()
        taskHandles[id] = nil
        cancelFlags[id] = nil
        showBanner(message)
        scheduleRetentionCleanup(id)
    }

    /// 完了・失敗したジョブを一覧から消す（進行中は残す）。
    func clearFinished() {
        let removed = jobs.filter(\.isFinished).map(\.id)
        jobs.removeAll { $0.isFinished }
        for id in removed {
            taskHandles[id] = nil
            cancelFlags[id] = nil
        }
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

    private func postImportCompletedNotification(jobTitle: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "取り込み完了"
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmedBody.isEmpty ? jobTitle : trimmedBody
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "transfer-succeed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 24時間後に自動削除。それまでは clearFinished まで残す。
    private func scheduleRetentionCleanup(_ id: UUID) {
        Task {
            let nanos = UInt64(Self.finishedRetention * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let idx = jobs.firstIndex(where: { $0.id == id }), jobs[idx].isFinished else { return }
            if let finishedAt = jobs[idx].finishedAt,
               Date().timeIntervalSince(finishedAt) + 1 < Self.finishedRetention {
                return
            }
            jobs.removeAll { $0.id == id }
            taskHandles[id] = nil
            cancelFlags[id] = nil
        }
    }
}
