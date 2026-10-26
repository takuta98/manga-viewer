import SwiftUI

struct ReaderView: View {
    let volume: MangaVolume

    @Environment(\.dismiss) private var dismiss
    @State private var pose: DuoPose = .open
    @State private var spreadIndex: Int = 0
    @State private var chromeVisible = true

    private let progress = ProgressStore.shared
    private var totalSpreads: Int {
        SpreadIndex.spreadCount(pageCount: volume.pageCount)
    }

    var body: some View {
        VStack(spacing: 16) {
            toolbar
            stage
            scrubber
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .background(Color(red: 0.05, green: 0.08, blue: 0.10).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear {
            spreadIndex = min(progress.spreadIndex(for: volume.id), totalSpreads - 1)
        }
        .onChange(of: spreadIndex) { _, newValue in
            progress.setSpreadIndex(newValue, for: volume.id)
        }
    }

    private var toolbar: some View {
        HStack {
            Button("← 書庫") { dismiss() }
                .foregroundStyle(Color("Mist"))

            Spacer()

            Picker("Pose", selection: $pose) {
                ForEach(DuoPose.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer()

            Text(volume.direction == .rtl ? "L←R" : "L→R")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color("AccentGold"))
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    private var stage: some View {
        DuoFrameView(pose: pose) {
            Group {
                switch pose {
                case .open:
                    openSpread
                case .closed:
                    closedPage
                case .table:
                    tablePose
                }
            }
            .overlay(alignment: .bottom) {
                if chromeVisible {
                    Text("\(volume.title) · \(progressLabel)")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .onTapGesture { chromeVisible.toggle() }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .gesture(turnGesture)
        .overlay {
            if pose != .table {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { handleEdgeTap(isLeft: true) }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { handleEdgeTap(isLeft: false) }
                }
            }
        }
    }

    private var openSpread: some View {
        let pages = SpreadIndex.pages(
            for: spreadIndex,
            pageAssetNames: volume.pageAssetNames,
            direction: volume.direction
        )
        return HStack(spacing: 14) {
            PagePaneView(imageName: pages.leftAsset, pageNumber: pages.leftPageNumber)
            PagePaneView(imageName: pages.rightAsset, pageNumber: pages.rightPageNumber)
        }
        .background(Color("PaperDeep"))
    }

    private var closedPage: some View {
        let page = SpreadIndex.closedPage(
            for: spreadIndex,
            pageAssetNames: volume.pageAssetNames,
            direction: volume.direction
        )
        return PagePaneView(imageName: page.asset, pageNumber: page.pageNumber)
            .background(Color("PaperDeep"))
    }

    private var tablePose: some View {
        let page = SpreadIndex.closedPage(
            for: spreadIndex,
            pageAssetNames: volume.pageAssetNames,
            direction: volume.direction
        )
        return VStack(spacing: 0) {
            PagePaneView(imageName: page.asset, pageNumber: page.pageNumber)
                .background(Color("PaperDeep"))
            HStack {
                Button(volume.direction == .rtl ? "戻る →" : "← 戻る") { goPrev() }
                Spacer()
                Text(progressLabel)
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Button(volume.direction == .rtl ? "← 進む" : "進む →") { goNext() }
            }
            .padding()
            .background(Color(red: 0.10, green: 0.12, blue: 0.14))
            .foregroundStyle(Color("Paper"))
        }
    }

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { Double(spreadIndex) },
                set: { spreadIndex = Int($0.rounded()) }
            ),
            in: 0...Double(max(totalSpreads - 1, 0)),
            step: 1
        )
        .environment(\.layoutDirection, volume.direction == .rtl ? .rightToLeft : .leftToRight)
        .tint(Color("AccentGold"))
    }

    private var progressLabel: String {
        switch pose {
        case .closed, .table:
            let page = SpreadIndex.closedPage(
                for: spreadIndex,
                pageAssetNames: volume.pageAssetNames,
                direction: volume.direction
            )
            return "p.\(page.pageNumber.map(String.init) ?? "—") / \(volume.pageCount)"
        case .open:
            return "spread \(spreadIndex + 1) / \(totalSpreads)"
        }
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) else { return }
                if volume.direction == .rtl {
                    if dx > 0 { goNext() } else { goPrev() }
                } else {
                    if dx > 0 { goPrev() } else { goNext() }
                }
            }
    }

    private func handleEdgeTap(isLeft: Bool) {
        // RTL: left = next, right = previous
        if volume.direction == .rtl {
            if isLeft { goNext() } else { goPrev() }
        } else {
            if isLeft { goPrev() } else { goNext() }
        }
    }

    private func goNext() {
        spreadIndex = min(spreadIndex + 1, totalSpreads - 1)
    }

    private func goPrev() {
        spreadIndex = max(spreadIndex - 1, 0)
    }
}
