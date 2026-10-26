import SwiftUI
import UIKit

struct PageTurnHost: UIViewControllerRepresentable {
    var pageCount: Int
    @Binding var index: Int
    var style: PageTurnStyle
    var rtl: Bool
    var reduceMotion: Bool
    var makePage: (Int) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let style: UIPageViewController.TransitionStyle = (self.style == .curl && !reduceMotion) ? .pageCurl : .scroll
        let pvc = UIPageViewController(transitionStyle: style, navigationOrientation: .horizontal, options: nil)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false
        context.coordinator.pvc = pvc
        if let first = context.coordinator.controller(for: index) {
            pvc.setViewControllers([first], direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let current = pvc.viewControllers?.first as? HostingPageController else { return }
        if current.index != index, let next = context.coordinator.controller(for: index) {
            let forward = rtl ? index < current.index : index > current.index
            pvc.setViewControllers([next], direction: forward ? .forward : .reverse, animated: !reduceMotion)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageTurnHost
        weak var pvc: UIPageViewController?
        private var cache: [Int: HostingPageController] = [:]

        init(_ parent: PageTurnHost) { self.parent = parent }

        func controller(for index: Int) -> HostingPageController? {
            guard index >= 0, index < parent.pageCount else { return nil }
            if let c = cache[index] { return c }
            let host = HostingPageController(rootView: parent.makePage(index), index: index)
            cache[index] = host
            return host
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let cur = viewController as? HostingPageController else { return nil }
            let next = parent.rtl ? cur.index + 1 : cur.index - 1
            return controller(for: next)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let cur = viewController as? HostingPageController else { return nil }
            let next = parent.rtl ? cur.index - 1 : cur.index + 1
            return controller(for: next)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let cur = pageViewController.viewControllers?.first as? HostingPageController else { return }
            parent.index = cur.index
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

final class HostingPageController: UIHostingController<AnyView> {
    let index: Int
    init(rootView: AnyView, index: Int) {
        self.index = index
        super.init(rootView: rootView)
        view.backgroundColor = .black
    }
    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError() }
}
