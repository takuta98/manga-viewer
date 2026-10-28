import SwiftUI
import UIKit

/// スワイプでページをめくる。タップは操作UIの表示切替のみ（ページ送りはしない）。
/// - 既定は pageCurl（ページめくり）
/// - 見開き（unitsPerScreen == 2）の curl は中央の綴じ目で1枚ずつめくる
/// - 右開きの単ページ curl は綴じ目を右端に置き、左端からめくる
/// - SwiftUI の update で表示中ページの rootView を毎フレーム差し替えない（アニメが消える）
struct PageBrowser: UIViewControllerRepresentable {
    /// めくりの単位（単ページ／スライド見開きは画面、curl 見開きは片ページ）の数
    var pageCount: Int
    /// 1画面に並べる単位の数（1 または 2）
    var unitsPerScreen: Int = 1
    /// 画面（見開き）インデックス
    @Binding var index: Int
    var style: PageTurnStyle
    var rtl: Bool
    var reduceMotion: Bool
    var pageRevision: Int
    var onToggleChrome: () -> Void
    var makePage: (Int) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let transition: UIPageViewController.TransitionStyle =
            (style == .curl && !reduceMotion) ? .pageCurl : .scroll
        let spread = transition == .pageCurl && unitsPerScreen == 2
        let spine: UIPageViewController.SpineLocation = spread ? .mid : (rtl ? .max : .min)
        let options: [UIPageViewController.OptionsKey: Any]? = transition == .pageCurl
            ? [.spineLocation: NSNumber(value: spine.rawValue)]
            : nil
        let controller = UIPageViewController(
            transitionStyle: transition,
            navigationOrientation: .horizontal,
            options: options
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = spread
        context.coordinator.pageController = controller
        context.coordinator.usesCurl = (transition == .pageCurl)
        context.coordinator.unitsPerScreen = spread ? 2 : 1

        // ページ送りはスワイプだけ。UIPageViewController 付属のタップめくりを無効化する。
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }

        // 画面のどこをタップしても操作UIの表示を切り替える。
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        controller.view.addGestureRecognizer(tap)

        context.coordinator.pageRevision = pageRevision
        context.coordinator.show(index: index, animated: false, publish: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.pageRevision != pageRevision || coordinator.cachedCount != pageCount {
            coordinator.cache.removeAll(keepingCapacity: true)
            coordinator.cachedCount = pageCount
            coordinator.pageRevision = pageRevision
            // 中身だけ変わったときは今のページを張り直す（アニメなし）
            if !coordinator.isBusy {
                coordinator.show(index: index, animated: false, publish: false)
            }
            return
        }

        // めくり／スワイプ中は SwiftUI から触らない（アニメを殺す・クラッシュの元）
        guard !coordinator.isBusy else { return }

        if coordinator.displayedIndex == index {
            return
        }

        // 外部（スライダー等）からの移動。隣接ならめくりアニメ、飛ページは瞬時。
        let animated = !reduceMotion && abs(coordinator.displayedIndex - index) == 1
        coordinator.show(index: index, animated: animated, publish: false)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PageBrowser
        weak var pageController: UIPageViewController?
        var cache: [Int: PageHostController] = [:]
        var cachedCount = -1
        var pageRevision = -1
        var displayedIndex = -1
        var usesCurl = true
        var unitsPerScreen = 1
        private var isSwiping = false
        private var isTurning = false

        var isBusy: Bool { isSwiping || isTurning }

        /// UIKit の「次（after / forward）」が読む順で何単位進むか。
        /// 右開きは常に逆方向: spine .max の before が「左端を右へめくる」進む動作になる。
        private var afterStep: Int {
            parent.rtl ? -1 : 1
        }

        private var screenCount: Int {
            (parent.pageCount + unitsPerScreen - 1) / unitsPerScreen
        }

        private func screenIndex(of controller: UIViewController?) -> Int? {
            (controller as? PageHostController).map { $0.pageIndex / unitsPerScreen }
        }

        init(_ parent: PageBrowser) {
            self.parent = parent
            self.cachedCount = parent.pageCount
        }

        private func publishIndex(_ index: Int) {
            guard parent.index != index else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.index != index {
                    self.parent.index = index
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !isBusy else { return }
            // ページ送りはスワイプのみ。タップはどこでも操作UIの切替。
            parent.onToggleChrome()
        }

        func show(index: Int, animated: Bool, publish: Bool) {
            guard let controller = pageController else { return }
            guard index >= 0, index < screenCount else { return }

            let first = index * unitsPerScreen
            var hosts: [PageHostController] = []
            for unit in first..<(first + unitsPerScreen) {
                guard let host = pageHost(for: unit, refresh: true) else { return }
                hosts.append(host)
            }
            // 見開きは [左, 右] で渡す。右開きは読む順の先頭が右。
            if unitsPerScreen == 2, parent.rtl {
                hosts.reverse()
            }

            if displayedIndex == index,
               screenIndex(of: controller.viewControllers?.first) == index {
                return
            }

            let from = displayedIndex >= 0
                ? displayedIndex
                : screenIndex(of: controller.viewControllers?.first)
            let direction: UIPageViewController.NavigationDirection
            if let from {
                let readingForward = index > from
                direction = (readingForward == (afterStep > 0)) ? .forward : .reverse
            } else {
                direction = .forward
            }

            let adjacent = from.map { abs($0 - index) == 1 } ?? true
            let canAnimate = animated && !isBusy && adjacent

            if canAnimate {
                isTurning = true
                // アニメ中に dataSource が干渉しないよう一時的に外す
                controller.dataSource = nil
                controller.setViewControllers(hosts, direction: direction, animated: true) { [weak self] finished in
                    guard let self else { return }
                    controller.dataSource = self
                    self.isTurning = false
                    if finished {
                        self.displayedIndex = index
                        if publish {
                            self.publishIndex(index)
                        }
                    } else if let current = self.screenIndex(of: controller.viewControllers?.first) {
                        self.displayedIndex = current
                    }
                }
            } else {
                controller.setViewControllers(hosts, direction: direction, animated: false)
                displayedIndex = index
                if publish {
                    publishIndex(index)
                }
            }
        }

        func pageHost(for index: Int, refresh: Bool) -> PageHostController? {
            guard index >= 0, index < parent.pageCount else { return nil }
            if let cached = cache[index] {
                if refresh {
                    cached.rootView = parent.makePage(index)
                }
                return cached
            }
            let host = PageHostController(rootView: parent.makePage(index), pageIndex: index)
            cache[index] = host
            return host
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageHostController else { return nil }
            return pageHost(for: current.pageIndex - afterStep, refresh: false)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageHostController else { return nil }
            return pageHost(for: current.pageIndex + afterStep, refresh: false)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isSwiping = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isSwiping = false
            guard finished,
                  let current = screenIndex(of: pageViewController.viewControllers?.first) else { return }
            displayedIndex = current
            if completed {
                publishIndex(current)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // ページめくりパンを優先し、タップはパンが失敗したときだけ
            false
        }
    }
}

final class PageHostController: UIHostingController<AnyView> {
    let pageIndex: Int

    init(rootView: AnyView, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
        view.backgroundColor = .black
        view.clipsToBounds = true
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
