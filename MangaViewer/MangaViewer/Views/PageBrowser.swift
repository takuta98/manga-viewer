import SwiftUI
import UIKit

/// スワイプと端タップでページを送る。中身に DragGesture を載せない。
struct PageBrowser: UIViewControllerRepresentable {
    var pageCount: Int
    @Binding var index: Int
    var style: PageTurnStyle
    var rtl: Bool
    var reduceMotion: Bool
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

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        controller.view.addGestureRecognizer(tap)

        context.coordinator.jump(to: index, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.cachedCount != pageCount {
            coordinator.cache.removeAll(keepingCapacity: true)
            coordinator.cachedCount = pageCount
        }

        // スワイプ／めくり中に SwiftUI から setViewControllers するとアニメが消え、
        // scroll では方向判定例外で落ちることがある。同期は静止時のみ・非アニメ。
        guard !coordinator.isInteractivelyAnimating else { return }
        if coordinator.displayedIndex == index {
            if let current = controller.viewControllers?.first as? PageHostController,
               current.pageIndex == index {
                current.rootView = makePage(index)
            }
            return
        }
        coordinator.jump(to: index, animated: false)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PageBrowser
        weak var pageController: UIPageViewController?
        var cache: [Int: PageHostController] = [:]
        var cachedCount = -1
        var displayedIndex = -1
        var isInteractivelyAnimating = false

        init(_ parent: PageBrowser) {
            self.parent = parent
            self.cachedCount = parent.pageCount
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let x = gesture.location(in: view).x
            let width = max(view.bounds.width, 1)
            if x <= width * 0.28 {
                move(forward: parent.rtl)
            } else if x >= width * 0.72 {
                move(forward: !parent.rtl)
            } else {
                parent.onToggleChrome()
            }
        }

        private func move(forward: Bool) {
            guard !isInteractivelyAnimating else { return }
            let next = forward ? parent.index + 1 : parent.index - 1
            guard next >= 0, next < parent.pageCount else { return }
            let animated = !parent.reduceMotion
            jump(to: next, animated: animated)
            if parent.index != next {
                parent.index = next
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func jump(to index: Int, animated: Bool) {
            guard let controller = pageController else { return }
            guard index >= 0, index < parent.pageCount else { return }
            guard let next = page(at: index) else { return }

            if displayedIndex == index,
               let current = controller.viewControllers?.first as? PageHostController,
               current.pageIndex == index {
                current.rootView = parent.makePage(index)
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

            // 隣接ページ以外の animated 移動は scroll で落ちやすいので無効化する。
            let adjacent = from.map { abs($0 - index) == 1 } ?? false
            let canAnimate = animated && adjacent && !isInteractivelyAnimating

            if canAnimate {
                isInteractivelyAnimating = true
                controller.setViewControllers([next], direction: direction, animated: true) { [weak self] finished in
                    guard let self else { return }
                    self.isInteractivelyAnimating = false
                    if finished {
                        self.displayedIndex = index
                    }
                }
            } else {
                controller.setViewControllers([next], direction: direction, animated: false)
                displayedIndex = index
            }
        }

        func page(at index: Int) -> PageHostController? {
            guard index >= 0, index < parent.pageCount else { return nil }
            if let cached = cache[index] {
                cached.rootView = parent.makePage(index)
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
            return page(at: next)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? PageHostController else { return nil }
            let next = parent.rtl ? current.pageIndex - 1 : current.pageIndex + 1
            return page(at: next)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isInteractivelyAnimating = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isInteractivelyAnimating = false
            guard finished,
                  let current = pageViewController.viewControllers?.first as? PageHostController else { return }
            displayedIndex = current.pageIndex
            if completed, parent.index != current.pageIndex {
                parent.index = current.pageIndex
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

final class PageHostController: UIHostingController<AnyView> {
    let pageIndex: Int

    init(rootView: AnyView, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
        view.backgroundColor = .black
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
