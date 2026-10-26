import ObjectiveC
import SwiftUI
import UIKit

enum PageTurnStyle: String, CaseIterable, Identifiable, Codable {
    case slide
    case curl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slide: return "スライド"
        case .curl: return "めくり"
        }
    }

    var uiTransition: UIPageViewController.TransitionStyle {
        switch self {
        case .slide: return .scroll
        case .curl: return .pageCurl
        }
    }
}

/// Full-screen paging with swipe and animated turns.
struct PageTurnHost: UIViewControllerRepresentable {
    var pageCount: Int
    @Binding var index: Int
    var isRTL: Bool
    var style: PageTurnStyle
    var onTapCenter: () -> Void
    var makePage: (Int) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: style.uiTransition,
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .black

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        pvc.view.addGestureRecognizer(tap)
        context.coordinator.pageViewController = pvc
        context.coordinator.onTapCenter = onTapCenter

        if let first = context.coordinator.controller(for: index) {
            pvc.setViewControllers([first], direction: .forward, animated: false)
            context.coordinator.currentIndex = index
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isRTL = isRTL
        coordinator.onTapCenter = onTapCenter

        // Rebuild if transition style changed.
        if pvc.transitionStyle != style.uiTransition {
            // UIPageViewController style is immutable; caller should .id(style) the representable.
        }

        guard pageCount > 0 else { return }
        let clamped = min(max(index, 0), pageCount - 1)
        guard coordinator.currentIndex != clamped,
              let vc = coordinator.controller(for: clamped) else { return }

        let movingForward: Bool = isRTL ? (clamped < coordinator.currentIndex) : (clamped > coordinator.currentIndex)
        pvc.setViewControllers(
            [vc],
            direction: movingForward ? .forward : .reverse,
            animated: true
        )
        coordinator.currentIndex = clamped
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageTurnHost
        var isRTL: Bool
        var currentIndex: Int = 0
        var onTapCenter: () -> Void = {}
        weak var pageViewController: UIPageViewController?
        private var cache: [Int: IdentifiedHost] = [:]

        init(_ parent: PageTurnHost) {
            self.parent = parent
            self.isRTL = parent.isRTL
            self.currentIndex = parent.index
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let x = gesture.location(in: view).x
            let w = max(view.bounds.width, 1)
            if x < w * 0.25 {
                setIndex(currentIndex + (isRTL ? 1 : -1), animated: true)
            } else if x > w * 0.75 {
                setIndex(currentIndex + (isRTL ? -1 : 1), animated: true)
            } else {
                onTapCenter()
            }
        }

        private func setIndex(_ next: Int, animated: Bool) {
            guard next >= 0, next < parent.pageCount else { return }
            guard let pvc = pageViewController, let vc = controller(for: next) else { return }
            let movingForward: Bool = isRTL ? (next < currentIndex) : (next > currentIndex)
            pvc.setViewControllers(
                [vc],
                direction: movingForward ? .forward : .reverse,
                animated: animated
            )
            currentIndex = next
            parent.index = next
        }

        func controller(for index: Int) -> UIViewController? {
            guard index >= 0, index < parent.pageCount else { return nil }
            if let cached = cache[index] {
                cached.host.rootView = parent.makePage(index)
                return cached.host
            }
            let host = UIHostingController(rootView: parent.makePage(index))
            host.view.backgroundColor = .black
            host.view.clipsToBounds = true
            cache[index] = IdentifiedHost(index: index, host: host)
            return host
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let idx = index(of: viewController) else { return nil }
            let step = isRTL ? 1 : -1
            return controller(for: idx + step)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let idx = index(of: viewController) else { return nil }
            let step = isRTL ? -1 : 1
            return controller(for: idx + step)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let visible = pageViewController.viewControllers?.first,
                  let idx = index(of: visible) else { return }
            currentIndex = idx
            parent.index = idx
        }

        private func index(of viewController: UIViewController) -> Int? {
            cache.first(where: { $0.value.host === viewController })?.key
        }
    }

    private final class IdentifiedHost {
        let index: Int
        let host: UIHostingController<AnyView>
        init(index: Int, host: UIHostingController<AnyView>) {
            self.index = index
            self.host = host
        }
    }
}
