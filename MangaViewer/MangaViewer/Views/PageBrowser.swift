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

        if let first = context.coordinator.page(at: index) {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.cachedCount != pageCount {
            context.coordinator.cache.removeAll(keepingCapacity: true)
            context.coordinator.cachedCount = pageCount
        }
        guard let current = controller.viewControllers?.first as? PageHostController else {
            if let first = context.coordinator.page(at: index) {
                controller.setViewControllers([first], direction: .forward, animated: false)
            }
            return
        }
        guard current.pageIndex != index,
              let next = context.coordinator.page(at: index) else { return }
        let goingForward = rtl ? index < current.pageIndex : index > current.pageIndex
        controller.setViewControllers(
            [next],
            direction: goingForward ? .forward : .reverse,
            animated: !reduceMotion
        )
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PageBrowser
        weak var pageController: UIPageViewController?
        var cache: [Int: PageHostController] = [:]
        var cachedCount = -1

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
            let next = forward ? parent.index + 1 : parent.index - 1
            guard next >= 0, next < parent.pageCount else { return }
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
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pageViewController.viewControllers?.first as? PageHostController else { return }
            parent.index = current.pageIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
