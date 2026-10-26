import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportHubView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var sources = RemoteSourceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showFiles = false
    @State private var showWiFi = false
    @State private var showTransfers = false
    @State private var addingKind: RemoteSourceKind?
    @State private var browseSource: RemoteSource?
    @ObservedObject private var activity = TransferActivityCenter.shared
    @ObservedObject private var progressStore = ProgressStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showFiles = true } label: {
                        Label(AppCopy.fromFiles, systemImage: "folder")
                    }
                    Button { showWiFi = true } label: {
                        Label(AppCopy.fromWiFi, systemImage: "wifi")
                    }
                } header: {
                    Text(AppCopy.thisDevice)
                } footer: {
                    Text(AppCopy.getWorksStayHint)
                }
                Section(AppCopy.newConnection) {
                    ForEach(RemoteSourceKind.allCases) { kind in
                        Button {
                            addingKind = kind
                        } label: {
                            Label(AppCopy.connectKind(kind.label), systemImage: kindIcon(kind))
                        }
                    }
                }
                if sources.sources.isEmpty {
                    Section {
                        Text(AppCopy.savedConnectionsHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(AppCopy.savedConnections) {
                        ForEach(sources.sources) { source in
                            Button {
                                browseSource = sources.hydrated(source)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.name)
                                        Text(source.kind.label + (source.host.isEmpty ? "" : " · \(source.host)"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let at = source.lastSuccessAt {
                                            Text("\(AppCopy.lastConnected)：\(at.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: kindIcon(source.kind))
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    sources.delete(source)
                                } label: {
                                    Label(AppCopy.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(AppCopy.getWorks)
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
                            var parts = [AppCopy.getWorks]
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
            }
            .environmentObject(library)
            .sheet(isPresented: $showTransfers) {
                TransferStatusView()
                    .environmentObject(library)
            }
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [
                    UTType(filenameExtension: "cbz") ?? .zip,
                    .zip,
                    .image,
                    .folder
                ],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls { startLocalImport(url) }
                }
            }
            .sheet(isPresented: Binding(
                get: { addingKind != nil },
                set: { if !$0 { addingKind = nil } }
            )) {
                if let kind = addingKind {
                    AddSourceView(kind: kind) { source in
                        sources.add(source)
                        browseSource = sources.hydrated(source)
                        addingKind = nil
                    }
                }
            }
            .sheet(item: $browseSource) { source in
                RemoteBrowserView(library: library, source: source)
                    .environmentObject(library)
            }
            .sheet(isPresented: $showWiFi) {
                WiFiTransferView(library: library)
                    .environmentObject(library)
            }
            .onChange(of: activity.pendingOpenVolumeId) { _, id in
                guard id != nil else { return }
                showTransfers = false
                showWiFi = false
                browseSource = nil
                addingKind = nil
                dismiss()
            }
        }
    }

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

    /// 読める作品が1件だけのとき、続きを読むか
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

    private func kindIcon(_ kind: RemoteSourceKind) -> String {
        switch kind {
        case .smb: return "externaldrive.connected.to.line.below"
        case .webdav: return "globe"
        case .sftp, .ftp: return "server.rack"
        case .opds: return "books.vertical"
        case .s3: return "cloud"
        case .http: return "link"
        }
    }

    private func startLocalImport(_ url: URL) {
        let displayTitle = UserFacingText.title(fromFileName: url.lastPathComponent)
        let job = activity.begin(title: displayTitle)
        let task = Task { @MainActor in
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let staged = try ImportStaging.fileURL(named: url.lastPathComponent)
                defer { ImportStaging.removeSession(containing: staged) }
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.copyItem(at: url, to: staged)
                if let existing = library.detectDuplicate(title: displayTitle) {
                    activity.succeed(job, message: AppCopy.alreadyHave, volumeId: existing.id)
                    return
                }
                let volume = try library.importURL(
                    staged,
                    folderId: library.currentFolderId,
                    titleOverride: displayTitle
                )
                activity.succeed(job, volumeId: volume.id)
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}
