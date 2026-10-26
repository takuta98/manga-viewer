import SwiftUI

struct LibraryView: View {
    var onOpen: (MangaVolume) -> Void
    private let progress = ProgressStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                shelf
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(LibraryBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DuoSpread")
                .font(.system(size: 56, weight: .semibold, design: .serif))
                .foregroundStyle(Color("Paper"))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("見開きのまま、読む。")
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(Color("Paper").opacity(0.88))

            Text("iPhone Duo の折り目を背表紙に。右ページから左へ、単行本どおりの RTL 見開きビューア。")
                .font(.system(size: 16))
                .foregroundStyle(Color("Mist"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .bottomLeading)
        .padding(.top, 24)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("書庫")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color("AccentGold"))
                .textCase(.uppercase)

            ForEach(Catalog.volumes) { volume in
                Button {
                    onOpen(volume)
                } label: {
                    HStack(spacing: 16) {
                        cover(for: volume)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(volume.title)
                                .font(.system(size: 24, weight: .medium, design: .serif))
                                .foregroundStyle(Color("Paper"))
                            Text(volume.titleEn)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color("Mist"))
                            let pct = progress.progressPercent(for: volume)
                            Text("\(volume.pageCount) pages · RTL · \(pct > 0 ? "\(pct)%" : "未読")")
                                .font(.system(size: 14))
                                .foregroundStyle(Color("Mist").opacity(0.9))
                                .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Text("SwiftUI · iPhone Duo · progress in UserDefaults")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color("Mist").opacity(0.65))
                .padding(.top, 24)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func cover(for volume: MangaVolume) -> some View {
        if let image = SampleImage.load(named: volume.coverAssetName) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 126)
                .clipped()
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        } else {
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(width: 84, height: 126)
        }
    }
}

private struct LibraryBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.08, blue: 0.10)
            RadialGradient(
                colors: [
                    Color(red: 0.17, green: 0.33, blue: 0.43).opacity(0.35),
                    .clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    Color(red: 0.70, green: 0.47, blue: 0.27).opacity(0.16),
                    .clear
                ],
                center: UnitPoint(x: 0.9, y: 0.15),
                startRadius: 10,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}
