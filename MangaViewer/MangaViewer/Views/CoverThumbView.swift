import SwiftUI
import UIKit

struct CoverThumbView: View {
    let imageURL: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Group {
                    if let imageURL, let ui = UIImage(contentsOfFile: imageURL.path) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.16)
                            Image(systemName: "book.closed")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct FolderThumbView: View {
    var coverURL: URL? = nil

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let coverURL, let ui = UIImage(contentsOfFile: coverURL.path) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(6)
                        }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "rectangle.stack.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// 表紙上の進捗チップ（本棚・Remote・入手完了で共通）
/// 呼び出し側は未読（0%）では出さない想定。未読表示が必要なときだけ percent==0 を渡す。
struct CoverProgressBadge: View {
    let percent: Int
    var compact: Bool = false

    private var label: String {
        percent >= 100 ? AppCopy.finishedReading : (percent > 0 ? "\(percent)%" : AppCopy.unread)
    }

    var body: some View {
        Group {
            if percent >= 100 {
                if compact {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                } else {
                    Label {
                        Text(label)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .labelStyle(.titleAndIcon)
                }
            } else {
                Text(label)
                    .monospacedDigit()
            }
        }
            .font(compact ? .system(size: 8, weight: .semibold) : .caption2.weight(.semibold))
            .padding(.horizontal, compact ? 3 : 6)
            .padding(.vertical, compact ? 1 : 3)
            .foregroundStyle(percent > 0 ? Color.primary : Color.secondary)
            .background {
                if percent >= 100 {
                    Capsule().fill(Color.green.opacity(0.32))
                } else if percent > 0 {
                    Capsule().fill(Color.accentColor.opacity(0.28))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .shadow(color: .black.opacity(compact ? 0 : 0.18), radius: 1, y: 0.5)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                percent >= 100
                    ? AppCopy.finishedReading
                    : (percent > 0 ? AppCopy.continueReading : AppCopy.unread)
            )
            .accessibilityValue(percent > 0 && percent < 100 ? "\(percent)%" : label)
            .accessibilityHint(
                percent >= 100
                    ? "\(AppCopy.finishedReading) · \(AppCopy.openToRead)"
                    : (percent > 0
                        ? "\(AppCopy.continueReading) \(percent)%"
                        : AppCopy.openToRead)
            )
            .accessibilityHidden(percent == 0)
    }
}

/// 表紙上のしおり数チップ
struct CoverBookmarkBadge: View {
    let count: Int
    var compact: Bool = false

    var body: some View {
        Label {
            Text("\(count)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.orange)
        }
        .font(compact ? .system(size: 8, weight: .semibold) : .caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, compact ? 3 : 6)
        .padding(.vertical, compact ? 1 : 3)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(compact ? 0 : 0.18), radius: 1, y: 0.5)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppCopy.bookmark)
        .accessibilityValue(
            count > 1
                ? "\(count) · \(AppCopy.bookmarkListFooter)"
                : "\(count)"
        )
        .accessibilityHint(AppCopy.bookmarkListFooter)
        .accessibilityHidden(count <= 0)
    }
}
