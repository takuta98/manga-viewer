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

        context.coordinator.apply(
            index: index,
            on: controller,
            animated: false
        )
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.cachedCount != pageCount {
            context.coordinator.cache.removeAll(keepingCapacity: true)
            context.coordinator.cachedCount = pageCount
        }

        // SwiftUI からの同期は必ず非アニメーション。
        // scroll スタイルで animated:true の setViewControllers を呼ぶと
        // "Failed to determine navigation direction for scroll" で落ちることがある。
        context.coordinator.apply(
            index: index,
            on: controller,
            animated: false
        )
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PageBrowser
        weak var pageController: UIPageViewController?
        var cache: [Int: PageHostController] = [:]
        var cachedCount = -1
        private var isAnimating = false
        /// 自分で index を書いた直後の mirror 更新を無視しないための表示中ページ。
        private var displayedIndex: Int = -1

        init(_ parent: PageBrowser) {
            self.parent = parent
            self.cachedCount = parent.pageCount
        }

        func apply(index: Int, on controller: UIPageViewController, animated: Bool) {
            guard !isAnimating else { return }
            guard index >= 0, index < parent.pageCount else { return }
            if displayedIndex == index,
               let current = controller.viewControllers?.first as? PageHostController,
               current.pageIndex == index {
                // 同じページでも SwiftUI の再描画に合わせて中身だけ更新する
                current.rootView = parent.makePage(index)
                return
            }
            guard let next = page(at: index) else { return }

            let from = displayedIndex >= 0 ? displayedIndex : (controller.viewControllers?.first as? PageHostController)?.pageIndex
            let direction: UIPageViewController.NavigationDirection
            if let from {
                let goingForward = parent.rtl ? index < from : index > from
                direction = goingForward ? .forward : .reverse
            } else {
                direction = .forward
            }

            // scroll では animated set が例外を投げやすいので、ここは常に false。
            controller.setViewControllers([next], direction: direction, animated: false)
            displayedIndex = index
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
            guard !isAnimating else { return }
            let next = forward ? parent.index + 1 : parent.index - 1
            guard next >= 0, next < parent.pageCount else { return }
            if let controller = pageController {
                apply(index: next, on: controller, animated: false)
            }
            parent.index = next
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            isAnimating = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isAnimating = false
            guard finished else { return }
            guard let current = pageViewController.viewControllers?.first as? PageHostController else { return }
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
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
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
