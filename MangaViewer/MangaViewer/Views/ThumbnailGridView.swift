import SwiftUI
import UIKit

struct ThumbnailGridView: View {
    let volume: MangaVolume
    var currentPage: Int = 0
    var bookmarked: Set<Int> = []
    var onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var onlyBookmarks = false

    private var pages: [Int] {
        if onlyBookmarks {
            // いまここから近いしおりを先に（しおり一覧と同じ）
            return bookmarked.sorted { abs($0 - currentPage) < abs($1 - currentPage) }
        }
        return Array(0..<volume.pageCount)
    }

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(AppCopy.bookmarkEmpty)
                        } icon: {
                            Image(systemName: "bookmark")
                                .foregroundStyle(.orange)
                        }
                    } description: {
                        Text(AppCopy.bookmarkEmptyBody)
                        let pagePct = Int(
                            (Double(currentPage + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        Text("\(AppCopy.hereNow) · \(currentPage + 1) / \(volume.pageCount) · \(pagePct)%")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ProgressView(
                            value: Double(currentPage + 1),
                            total: Double(max(volume.pageCount, 1))
                        )
                        .tint(.accentColor)
                        .frame(maxWidth: 160)
                        .padding(.top, 4)
                        Text(AppCopy.bookmarkListFooter)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    } actions: {
                        if onlyBookmarks {
                            Button(AppCopy.thumbnails) { onlyBookmarks = false }
                                .buttonStyle(.bordered)
                                .accessibilityHint(AppCopy.thumbnails)
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onPick(currentPage)
                            } label: {
                                let pagePct = Int(
                                    (Double(currentPage + 1) / Double(max(volume.pageCount, 1)) * 100)
                                        .rounded()
                                )
                                Label(
                                    "\(AppCopy.hereNow) · \(currentPage + 1) · \(pagePct)%",
                                    systemImage: "book"
                                )
                                .monospacedDigit()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(AppCopy.openToRead)
                            .accessibilityValue(
                                {
                                    let pagePct = Int(
                                        (Double(currentPage + 1) / Double(max(volume.pageCount, 1)) * 100)
                                            .rounded()
                                    )
                                    return "\(AppCopy.hereNow)、\(currentPage + 1) / \(volume.pageCount) · \(pagePct)%"
                                }()
                            )
                            .accessibilityHint(AppCopy.currentPageLabel)
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            if onlyBookmarks {
                                let pagePct = Int(
                                    (Double(currentPage + 1) / Double(max(volume.pageCount, 1)) * 100)
                                        .rounded()
                                )
                                Text(
                                    "\(AppCopy.bookmark) \(bookmarked.count) · \(AppCopy.hereNow) \(currentPage + 1) / \(volume.pageCount) · \(pagePct)%"
                                )
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .accessibilityLabel(AppCopy.bookmarkList)
                                .accessibilityValue(
                                    "\(AppCopy.bookmark) \(bookmarked.count)、\(AppCopy.hereNow) \(pagePct)%"
                                )
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                                ForEach(pages, id: \.self) { i in
                                    Button {
                                        UIImpactFeedbackGenerator(
                                            style: (onlyBookmarks || bookmarked.contains(i))
                                                && i != currentPage ? .medium : .light
                                        ).impactOccurred()
                                        onPick(i)
                                    } label: {
                                        Color.clear
                                            .aspectRatio(2 / 3, contentMode: .fit)
                                            .overlay {
                                                if let url = volume.pageURL(at: i),
                                                   let img = UIImage(contentsOfFile: url.path) {
                                                    Image(uiImage: img)
                                                        .resizable()
                                                        .scaledToFill()
                                                } else {
                                                    Rectangle().fill(Color.secondary.opacity(0.3))
                                                }
                                            }
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            .overlay {
                                                if i == currentPage {
                                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                        .strokeBorder(.tint, lineWidth: 2)
                                                }
                                            }
                                            .overlay(alignment: .topLeading) {
                                                if i == currentPage {
                                                    Text(AppCopy.hereNow)
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 2)
                                                        .background(.tint, in: Capsule())
                                                        .foregroundStyle(.white)
                                                        .padding(4)
                                                }
                                            }
                                            .overlay(alignment: .topTrailing) {
                                                if bookmarked.contains(i) {
                                                    Image(systemName: "bookmark.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(.orange)
                                                        .padding(4)
                                                }
                                            }
                                            .overlay(alignment: .bottom) {
                                                let pagePct = Int(
                                                    (Double(i + 1) / Double(max(volume.pageCount, 1)) * 100)
                                                        .rounded()
                                                )
                                                let relative: String = {
                                                    // しおり絞り込み時のみ相対距離を短く（セル幅を食わない）
                                                    guard onlyBookmarks, i != currentPage else { return "" }
                                                    let d = i - currentPage
                                                    if d > 0 { return " · +\(d)" }
                                                    if d < 0 { return " · \(d)" }
                                                    return ""
                                                }()
                                                Text("\(i + 1) · \(pagePct)%\(relative)")
                                                    .font(.caption2.monospacedDigit())
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                                    .padding(4)
                                                    .frame(maxWidth: .infinity)
                                                    .background(.black.opacity(0.55))
                                                    .foregroundStyle(.white)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .id(i)
                                    .accessibilityLabel("\(i + 1) \(AppCopy.pageCountSuffix)")
                                    .accessibilityValue(
                                        {
                                            let pagePct = Int(
                                                (Double(i + 1) / Double(max(volume.pageCount, 1)) * 100)
                                                    .rounded()
                                            )
                                            var parts: [String] = ["\(pagePct)%"]
                                            if i == currentPage { parts.append(AppCopy.hereNow) }
                                            if bookmarked.contains(i) { parts.append(AppCopy.bookmark) }
                                            if i != currentPage {
                                                let d = i - currentPage
                                                if d > 0 { parts.append(AppCopy.bookmarkPagesAhead(d)) }
                                                else if d < 0 { parts.append(AppCopy.bookmarkPagesBehind(-d)) }
                                            }
                                            return parts.joined(separator: "、")
                                        }()
                                    )
                                    .accessibilityHint(
                                        {
                                            let pagePct = Int(
                                                (Double(i + 1) / Double(max(volume.pageCount, 1)) * 100)
                                                    .rounded()
                                            )
                                            if bookmarked.contains(i) || onlyBookmarks {
                                                return "\(AppCopy.jumpToPage) · \(pagePct)%"
                                            }
                                            return "\(AppCopy.openToRead) · \(pagePct)%"
                                        }()
                                    )
                                }
                            }
                            .padding()
                        }
                        .onAppear {
                            let target = pages.contains(currentPage)
                                ? currentPage
                                : pages.first
                            if let target {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                        .onChange(of: onlyBookmarks) { _, _ in
                            let target = pages.contains(currentPage)
                                ? currentPage
                                : pages.first
                            if let target {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle(
                onlyBookmarks
                    ? (bookmarked.isEmpty
                        ? AppCopy.bookmarkList
                        : "\(AppCopy.bookmarkList)（\(bookmarked.count)）")
                    : AppCopy.thumbnails
            )
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
                            let pagePct = Int(
                                (Double(currentPage + 1) / Double(max(volume.pageCount, 1)) * 100)
                                    .rounded()
                            )
                            var parts = [
                                "\(AppCopy.hereNow) \(currentPage + 1) / \(volume.pageCount) · \(pagePct)%",
                            ]
                            if !bookmarked.isEmpty {
                                parts.append("\(AppCopy.bookmark) \(bookmarked.count)")
                            }
                            if onlyBookmarks {
                                parts.append(AppCopy.bookmarkList)
                            }
                            return parts.joined(separator: "、")
                        }()
                    )
                    .accessibilityHint(AppCopy.currentPageLabel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !bookmarked.isEmpty {
                        Button {
                            onlyBookmarks.toggle()
                        } label: {
                            Label {
                                Text("\(AppCopy.bookmark) \(bookmarked.count)")
                                    .monospacedDigit()
                            } icon: {
                                Image(systemName: onlyBookmarks ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(.orange)
                            }
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                        }
                        .tint(onlyBookmarks ? .orange : .accentColor)
                        .accessibilityLabel(AppCopy.bookmarkList)
                        .accessibilityValue(
                            {
                                let pagePct = Int(
                                    (Double(currentPage + 1) / Double(max(volume.pageCount, 1)) * 100)
                                        .rounded()
                                )
                                let mode = onlyBookmarks ? AppCopy.bookmarkList : AppCopy.thumbnails
                                return "\(mode)、\(AppCopy.bookmark) \(bookmarked.count)、\(AppCopy.hereNow) \(pagePct)%"
                            }()
                        )
                        .accessibilityHint(
                            onlyBookmarks ? AppCopy.thumbnails : AppCopy.bookmarkListFooter
                        )
                    }
                }
            }
        }
    }
}
