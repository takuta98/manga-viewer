import CoreGraphics
import Foundation

/// 画面サイズ／向きから実際のページレイアウトを決める。
/// アウター・インナー縦は常に1ページ。見開きは十分な横長のときだけ。
enum DisplayLayoutResolver {
    static func resolve(containerSize: CGSize, preference: PageLayoutMode) -> PageLayoutMode {
        if preference == .webtoon {
            return .webtoon
        }
        guard containerSize.width > 1, containerSize.height > 1 else {
            return .single
        }
        let landscape = containerSize.width > containerSize.height
        // 縦表示（アウター／インナー縦）は必ず単ページ
        guard landscape else {
            return .single
        }
        // 横でも狭いと見開きは崩れる（目安: 幅が高さの 1.25 倍以上）
        let aspect = containerSize.width / containerSize.height
        guard aspect >= 1.25 else {
            return .single
        }
        // ユーザーが見開きを望むときだけ見開き
        return preference == .spread ? .spread : .single
    }

    static var explainsToUser: String {
        "縦画面は常に1ページ。横に広く開いたときだけ見開きになります。"
    }
}
