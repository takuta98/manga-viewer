import SwiftUI
import UIKit

/// スワイプと端タップでページをめくる。
/// - 既定は pageCurl（ページめくり）
/// - SwiftUI の update で表示中ページの rootView を毎フレーム差し替えない（アニメが消える）
struct PageBrowser: UIViewControllerRepresentable {
    var pageCount: Int
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
        let controller = UIPageViewController(
            transitionStyle: transition,
            navigationOrientation: .horizontal,
            options: nil
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        context.coordinator.pageController = controller
        context.coordinator.usesCurl = (transition == .pageCurl)

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
        private var isSwiping = false
        private var isTurning = false

        var isBusy: Bool { isSwiping || isTurning }

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
            guard let view = gesture.view, !isBusy else { return }
            let x = gesture.location(in: view).x
            let width = max(view.bounds.width, 1)
            if x <= width * 0.28 {
                turn(forward: parent.rtl)
            } else if x >= width * 0.72 {
                turn(forward: !parent.rtl)
            } else {
                parent.onToggleChrome()
            }
        }

        private func turn(forward: Bool) {
            let next = forward ? parent.index + 1 : parent.index - 1
            guard next >= 0, next < parent.pageCount else { return }
            let animated = !parent.reduceMotion
            show(index: next, animated: animated, publish: true)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func show(index: Int, animated: Bool, publish: Bool) {
            guard let controller = pageController else { return }
            guard index >= 0, index < parent.pageCount else { return }
            guard let destination = pageHost(for: index, refresh: true) else { return }

            if displayedIndex == index,
               let current = controller.viewControllers?.first as? PageHostController,
               current.pageIndex == index {
                return
            }

            let from = displayedIndex >= 0
                ? displayedIndex
                : (controller.viewControllers?.first as? PageHostController)?.pageIndex
            let direction: UIPageViewController.NavigationDirection
            if let from {
                let goingForward = parent.rtl ? index < from : index > from
                direction = goingForward ? .forward : .reverse
            } else {
                direction = .forward
            }

            let adjacent = from.map { abs($0 - index) == 1 } ?? true
            // curl は animated set が安定。scroll は隣接のみアニメにする。
            let canAnimate: Bool
            if !animated || isBusy {
                canAnimate = false
            } else if usesCurl {
                canAnimate = adjacent
            } else {
                canAnimate = adjacent
            }

            if canAnimate {
                isTurning = true
                // アニメ中に dataSource が干渉しないよう一時的に外す
                controller.dataSource = nil
                controller.setViewControllers([destination], direction: direction, animated: true) { [weak self] finished in
                    guard let self else { return }
                    controller.dataSource = self
                    self.isTurning = false
                    if finished {
                        self.displayedIndex = index
                        if publish {
                            self.publishIndex(index)
                        }
                    } else if let current = controller.viewControllers?.first as? PageHostController {
                        self.displayedIndex = current.pageIndex
                    }
                }
            } else {
                controller.setViewControllers([destination], direction: direction, animated: false)
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
            let next = parent.rtl ? current.pageIndex + 1 : current.pageIndex - 1
            return pageHost(for: next, refresh: false)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageHostController else { return nil }
            let next = parent.rtl ? current.pageIndex - 1 : current.pageIndex + 1
            return pageHost(for: next, refresh: false)
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
                  let current = pageViewController.viewControllers?.first as? PageHostController else { return }
            displayedIndex = current.pageIndex
            if completed {
                publishIndex(current.pageIndex)
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
