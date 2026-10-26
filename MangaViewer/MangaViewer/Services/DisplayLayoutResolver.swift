import CoreGraphics
import Foundation

enum DisplayLayoutResolver {
    static func resolve(containerSize: CGSize, preference: PageLayoutMode) -> PageLayoutMode {
        if preference == .webtoon { return .webtoon }
        guard containerSize.width > 1, containerSize.height > 1 else { return .single }
        guard containerSize.width > containerSize.height else { return .single }
        let aspect = containerSize.width / containerSize.height
        guard aspect >= 1.25 else { return .single }
        return preference == .spread ? .spread : .single
    }

    static var explainsToUser: String { AppCopy.layoutExplain }
}
