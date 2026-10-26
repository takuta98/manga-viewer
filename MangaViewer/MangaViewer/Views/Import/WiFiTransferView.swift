import SwiftUI
import UIKit

struct WiFiTransferView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var server = WiFiTransferServer()
    @ObservedObject private var activity = TransferActivityCenter.shared
    @ObservedObject private var progressStore = ProgressStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showTransfers = false
    @State private var lastVolumeId: UUID?

    private var readyDownloadCount: Int {
        activity.jobs.filter {
            $0.isFinished && !$0.isFailed && !$0.isCancelled && $0.volumeId != nil
                && library.volumes.contains { vol in vol.id == $0.volumeId }
        }.count
    }

    private var singleReadyPercent: Int? {
        let _ = progressStore.revision
        guard readyDownloadCount == 1,
              let job = activity.jobs.first(where: { job in
                  guard job.isFinished, !job.isFailed, !job.isCancelled,
                        let vid = job.volumeId else { return false }
                  return library.volumes.contains { $0.id == vid }
              }),
              let vid = job.volumeId,
              let volume = library.volumes.first(where: { $0.id == vid }) else { return nil }
        return progressStore.progressPercent(for: volume, coverAlone: true, layout: .single)
    }

    private var singleReadyResume: Bool {
        guard let pct = singleReadyPercent else { return false }
        return pct > 0 && pct < 100
    }

    private var singleReadyMarks: Int {
        let _ = progressStore.revision
        guard readyDownloadCount == 1,
              let job = activity.jobs.first(where: { job in
                  guard job.isFinished, !job.isFailed, !job.isCancelled,
                        let vid = job.volumeId else { return false }
                  return library.volumes.contains { $0.id == vid }
              }),
              let vid = job.volumeId else { return 0 }
        return progressStore.bookmarks(for: vid).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(AppCopy.wifiInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(server.addressText)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(server.addressText)
                Text(server.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let name = server.lastSavedName {
                    VStack(spacing: 12) {
                        if let lastVolumeId,
                           let volume = library.volumes.first(where: { $0.id == lastVolumeId }) {
                            let pct = ProgressStore.shared.progressPercent(
                                for: volume,
                                coverAlone: true,
                                layout: .single
                            )
                            let marks = ProgressStore.shared.bookmarks(for: volume.id).count
                            let resume = pct > 0 && pct < 100
                            ZStack(alignment: .bottomLeading) {
                                CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 6)
                                    .frame(width: 72)
                                if pct > 0 || marks > 0 {
                                    HStack(spacing: 4) {
                                        if pct > 0 {
                                            CoverProgressBadge(percent: pct)
                                        }
                                        if marks > 0 {
                                            CoverBookmarkBadge(count: marks)
                                        }
                                    }
                                    .padding(4)
                                }
                            }
                            Text(AppCopy.downloadFinished)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                            if resume {
                                ProgressView(value: Double(pct), total: 100)
                                    .tint(.accentColor)
                                    .frame(maxWidth: 160)
                                Text(
                                    marks > 0
                                        ? "\(pct)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marks)"
                                        : "\(pct)% · \(AppCopy.continueReading)"
                                )
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else if pct >= 100 {
                                Text(
                                    marks > 0
                                        ? "\(AppCopy.finishedReading) · \(AppCopy.bookmark) \(marks)"
                                        : AppCopy.finishedReading
                                )
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            if marks > 0, !resume, pct < 100 {
                                Label {
                                    Text("\(AppCopy.bookmark) \(marks) · \(AppCopy.bookmarkListFooter)")
                                        .monospacedDigit()
                                } icon: {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.orange)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                            }
                            Button {
                                activity.toast = nil
                                activity.pendingOpenVolumeId = lastVolumeId
                                UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                                dismiss()
                            } label: {
                                Label(
                                    resume
                                        ? (marks > 0
                                            ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                            : "\(AppCopy.continueReading) \(pct)%")
                                        : (marks > 0
                                            ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                            : AppCopy.readNow),
                                    systemImage: resume ? "play.fill" : "book"
                                )
                                .monospacedDigit()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(resume ? AppCopy.continueReading : AppCopy.readNow)
                            .accessibilityHint(
                                resume
                                    ? (marks > 0
                                        ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                                        : AppCopy.resumeReading)
                                    : (marks > 0
                                        ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                                        : AppCopy.openToRead)
                            )
                            .accessibilityValue(
                                {
                                    var parts = [name]
                                    if resume { parts.append("\(pct)%") }
                                    if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
                                    return parts.joined(separator: "、")
                                }()
                            )
                        } else {
                            Text(AppCopy.downloadFinished)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(AppCopy.downloadFinished)、\(name)")
                }
                Spacer()
            }
            .padding()
            .navigationTitle(AppCopy.wifiTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .accessibilityLabel(AppCopy.close)
                    .accessibilityValue(
                        {
                            var parts = [AppCopy.wifiTitle]
                            if readyDownloadCount > 0 {
                                parts.append("\(AppCopy.readyToRead) \(readyDownloadCount)")
                            }
                            if singleReadyResume, let pct = singleReadyPercent {
                                parts.append("\(AppCopy.continueReading) \(pct)%")
                            }
                            if singleReadyMarks > 0 {
                                parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                            }
                            return parts.joined(separator: "、")
                        }()
                    )
                    .accessibilityHint(AppCopy.libraryTitle)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if activity.activeCount == 0,
                           readyDownloadCount == 1,
                           let job = activity.jobs.first(where: { job in
                               guard job.isFinished, !job.isFailed, !job.isCancelled,
                                     let vid = job.volumeId else { return false }
                               return library.volumes.contains { $0.id == vid }
                           }),
                           let vid = job.volumeId {
                            activity.toast = nil
                            activity.pendingOpenVolumeId = vid
                            UIImpactFeedbackGenerator(
                                style: singleReadyResume ? .medium : .light
                            ).impactOccurred()
                        } else {
                            showTransfers = true
                        }
                    } label: {
                        let _ = progressStore.revision
                        if activity.activeCount > 0 {
                            Text(AppCopy.downloadActiveCount(activity.activeCount))
                                .font(.caption.weight(.semibold))
                        } else if readyDownloadCount > 0 {
                            let resume = singleReadyResume
                            let pct = singleReadyPercent
                            let marks = singleReadyMarks
                            Label(
                                readyDownloadCount == 1
                                    ? (resume
                                        ? (marks > 0
                                            ? "\(AppCopy.continueReading) \(pct ?? 0)% · \(AppCopy.bookmark) \(marks)"
                                            : (pct.map { "\(AppCopy.continueReading) \($0)%" }
                                                ?? AppCopy.continueReading))
                                        : (marks > 0
                                            ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                            : AppCopy.readNow))
                                    : "\(readyDownloadCount)",
                                systemImage: readyDownloadCount == 1
                                    ? (resume ? "play.fill" : "book")
                                    : "books.vertical"
                            )
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .labelStyle(.titleAndIcon)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .accessibilityLabel(
                        readyDownloadCount == 1 && activity.activeCount == 0
                            ? (singleReadyResume ? AppCopy.continueReading : AppCopy.readNow)
                            : AppCopy.downloads
                    )
                    .accessibilityValue(
                        activity.activeCount > 0
                            ? AppCopy.downloadActiveCount(activity.activeCount)
                            : (readyDownloadCount > 0
                                ? {
                                    if readyDownloadCount == 1 && singleReadyResume {
                                        var parts = ["\(AppCopy.readyToRead) · \(singleReadyPercent ?? 0)%"]
                                        if singleReadyMarks > 0 {
                                            parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }
                                    if readyDownloadCount == 1 && singleReadyMarks > 0 {
                                        return "\(AppCopy.readyToRead) · \(AppCopy.bookmark) \(singleReadyMarks)"
                                    }
                                    return "\(AppCopy.readyToRead) \(readyDownloadCount)"
                                }()
                                : AppCopy.downloadEmptyTitle)
                    )
                    .accessibilityHint(
                        readyDownloadCount == 1 && activity.activeCount == 0
                            ? (singleReadyResume
                                ? (singleReadyMarks > 0
                                    ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(singleReadyMarks)"
                                    : AppCopy.resumeReading)
                                : (singleReadyMarks > 0
                                    ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(singleReadyMarks)"
                                    : AppCopy.openToRead))
                            : AppCopy.tapToReadHint
                    )
                }
            }
            .overlay(alignment: .top) { ActivityOverlayView() }
            .safeAreaInset(edge: .bottom) {
                DownloadStatusChip { showTransfers = true }
                    .environmentObject(library)
            }
            .environmentObject(library)
            .sheet(isPresented: $showTransfers) {
                TransferStatusView()
                    .environmentObject(library)
            }
            .onAppear {
                server.statusText = AppCopy.wifiWaiting
                server.onFileReceived = { url in
                    let displayTitle = UserFacingText.title(fromFileName: url.lastPathComponent)
                    let job = activity.begin(title: displayTitle)
                    let task = Task { @MainActor in
                        do {
                            defer { ImportStaging.removeSession(containing: url) }
                            if let existing = library.detectDuplicate(title: displayTitle) {
                                activity.succeed(job, message: AppCopy.alreadyHave, volumeId: existing.id)
                                server.statusText = AppCopy.alreadyHave
                                server.lastSavedName = existing.title
                                lastVolumeId = existing.id
                                return
                            }
                            let volume = try library.importURL(
                                url,
                                folderId: library.currentFolderId,
                                titleOverride: displayTitle
                            )
                            activity.succeed(job, volumeId: volume.id)
                            server.statusText = AppCopy.downloadFinished
                            server.lastSavedName = volume.title
                            lastVolumeId = volume.id
                        } catch {
                            activity.fail(job, message: error.localizedDescription)
                            server.statusText = error.localizedDescription
                        }
                    }
                    activity.attachTask(job, task)
                }
                server.start()
            }
            .onDisappear { server.stop() }
            .onChange(of: activity.pendingOpenVolumeId) { _, id in
                guard id != nil else { return }
                showTransfers = false
                dismiss()
            }
        }
    }
}
