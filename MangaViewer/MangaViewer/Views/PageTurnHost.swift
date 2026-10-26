import SwiftUI
import UIKit

enum PageTurnStyle: String, CaseIterable, Identifiable, Codable {
    case curl
    case slide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .curl: return "めくり（カール）"
        case .slide: return "スライド"
        }
    }

    var uiTransition: UIPageViewController.TransitionStyle {
        switch self {
        case .curl: return .pageCurl
        case .slide: return .scroll
        }
    }
}

/// スワイプ／タップでページ送り。ズームは UIScrollView 側に任せ、ジェスチャ競合を避ける。
struct PageTurnHost: UIViewControllerRepresentable {
    var pageCount: Int
    @Binding var index: Int
    var isRTL: Bool
    var style: PageTurnStyle
    /// `accessibilityReduceMotion` 時はカール禁止のスライド＋非アニメ遷移。
    var animateTransitions: Bool = true
    var onTapCenter: () -> Void
    var makePage: (Int) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options: [UIPageViewController.OptionsKey: Any]?
        if style == .curl {
            // RTL 漫画は右綴じに寄せる
            let spine: UIPageViewController.SpineLocation = isRTL ? .max : .min
            options = [.spineLocation: spine.rawValue]
        } else {
            options = nil
        }
        let pvc = UIPageViewController(
            transitionStyle: style.uiTransition,
            navigationOrientation: .horizontal,
            options: options
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .black
        if style == .curl {
            pvc.isDoubleSided = true
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        pvc.view.addGestureRecognizer(tap)
        context.coordinator.singleTap = tap

        context.coordinator.pageViewController = pvc
        context.coordinator.onTapCenter = onTapCenter
        context.coordinator.haptic.prepare()

        if let first = context.coordinator.controller(for: index) {
            if let zoom = first as? ZoomHostingController {
                zoom.attachSingleTapDependency(tap)
            }
            pvc.setViewControllers([first], direction: .forward, animated: false)
            context.coordinator.currentIndex = index
        }
        context.coordinator.setPageScrollEnabled(true)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isRTL = isRTL
        coordinator.onTapCenter = onTapCenter

        guard pageCount > 0 else { return }
        let clamped = min(max(index, 0), pageCount - 1)
        guard coordinator.currentIndex != clamped,
              let vc = coordinator.controller(for: clamped),
              pvc.viewControllers?.first !== vc else {
            if let host = pvc.viewControllers?.first as? ZoomHostingController {
                host.apply(rootView: makePage(coordinator.currentIndex))
            }
            return
        }

        let movingForward = isRTL ? (clamped < coordinator.currentIndex) : (clamped > coordinator.currentIndex)
        pvc.setViewControllers(
            [vc],
            direction: movingForward ? .forward : .reverse,
            animated: animateTransitions
        ) { finished in
            if finished {
                coordinator.currentIndex = clamped
            }
        }
        coordinator.currentIndex = clamped
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageTurnHost
        var isRTL: Bool
        var currentIndex: Int = 0
        var onTapCenter: () -> Void = {}
        weak var pageViewController: UIPageViewController?
        weak var singleTap: UITapGestureRecognizer?
        /// 完了したページめくりにつき light impact を一度だけ。
        let haptic = UIImpactFeedbackGenerator(style: .light)
        private var cache: [Int: ZoomHostingController] = [:]

        init(_ parent: PageTurnHost) {
            self.parent = parent
            self.isRTL = parent.isRTL
            self.currentIndex = parent.index
        }

        /// UIPageViewController 内部の UIScrollView を完全に止める／再開する。
        func setPageScrollEnabled(_ enabled: Bool) {
            guard let root = pageViewController?.view else { return }
            func visit(_ view: UIView) {
                if let scroll = view as? UIScrollView {
                    if scroll.delegate is ZoomHostingController { return }
                    scroll.isScrollEnabled = enabled
                }
                for child in view.subviews {
                    visit(child)
                }
            }
            visit(root)
        }

        private func bindZoomCallbacks(_ host: ZoomHostingController) {
            host.onZoomChanged = { [weak self] zoomed in
                self?.setPageScrollEnabled(!zoomed)
            }
            setPageScrollEnabled(!host.isZoomed)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            if let zoom = pageViewController?.viewControllers?.first as? ZoomHostingController,
               zoom.isZoomed {
                return
            }
            let x = gesture.location(in: view).x
            let w = max(view.bounds.width, 1)
            if x < w * 0.28 {
                turn(by: isRTL ? 1 : -1)
            } else if x > w * 0.72 {
                turn(by: isRTL ? -1 : 1)
            } else {
                onTapCenter()
            }
        }

        private func turn(by delta: Int) {
            let next = currentIndex + delta
            guard next >= 0, next < parent.pageCount else { return }
            guard let pvc = pageViewController, let vc = controller(for: next) else { return }
            let movingForward = isRTL ? (next < currentIndex) : (next > currentIndex)
            pvc.setViewControllers(
                [vc],
                direction: movingForward ? .forward : .reverse,
                animated: parent.animateTransitions
            )
            currentIndex = next
            parent.index = next
        }

        func controller(for index: Int) -> UIViewController? {
            guard index >= 0, index < parent.pageCount else { return nil }
            if let cached = cache[index] {
                cached.apply(rootView: parent.makePage(index))
                bindZoomCallbacks(cached)
                if let singleTap {
                    cached.attachSingleTapDependency(singleTap)
                }
                return cached
            }
            let host = ZoomHostingController(rootView: parent.makePage(index))
            bindZoomCallbacks(host)
            if let singleTap {
                host.attachSingleTapDependency(singleTap)
            }
            cache[index] = host
            if cache.count > 12 {
                let keep = Set((index - 2)...(index + 2))
                for key in cache.keys where !keep.contains(key) && key != index {
                    cache.removeValue(forKey: key)
                }
            }
            return host
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            if let zoom = viewController as? ZoomHostingController, zoom.isZoomed {
                return nil
            }
            guard let idx = index(of: viewController) else { return nil }
            return controller(for: idx + (isRTL ? 1 : -1))
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            if let zoom = viewController as? ZoomHostingController, zoom.isZoomed {
                return nil
            }
            guard let idx = index(of: viewController) else { return nil }
            return controller(for: idx + (isRTL ? -1 : 1))
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
            let fromIdx = previousViewControllers.compactMap { index(of: $0) }.first
            if fromIdx != idx {
                haptic.impactOccurred()
            }
            currentIndex = idx
            parent.index = idx
            if let zoom = visible as? ZoomHostingController {
                zoom.resetZoom(animated: false)
                setPageScrollEnabled(true)
            }
        }

        private func index(of viewController: UIViewController) -> Int? {
            cache.first(where: { $0.value === viewController })?.key
        }
    }
}

/// ピンチズーム付きホスト。拡大中はページ送りを止める。
final class ZoomHostingController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let host: UIHostingController<AnyView>
    private(set) var isZoomed = false
    var onZoomChanged: ((Bool) -> Void)?

    init(rootView: AnyView) {
        self.host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(rootView: AnyView) {
        host.rootView = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        addChild(host)
        host.view.backgroundColor = .black
        host.view.frame = scrollView.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(host.view)
        host.didMove(toParent: self)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        self.doubleTap = doubleTap
        if let pendingSingleTap {
            pendingSingleTap.require(toFail: doubleTap)
        }
    }

    private var doubleTap: UITapGestureRecognizer?
    private weak var pendingSingleTap: UITapGestureRecognizer?

    func attachSingleTapDependency(_ singleTap: UITapGestureRecognizer) {
        pendingSingleTap = singleTap
        if let doubleTap {
            singleTap.require(toFail: doubleTap)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale <= 1.01 {
            host.view.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        host.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let zoomed = scrollView.zoomScale > 1.05
        if zoomed != isZoomed {
            isZoomed = zoomed
            onZoomChanged?(zoomed)
        }
        centerContent()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let zoomed = scale > 1.05
        if zoomed != isZoomed {
            isZoomed = zoomed
            onZoomChanged?(zoomed)
        }
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(1, animated: animated)
        if isZoomed {
            isZoomed = false
            onZoomChanged?(false)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.05 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: host.view)
            let zoom: CGFloat = 2.5
            let size = CGSize(
                width: scrollView.bounds.width / zoom,
                height: scrollView.bounds.height / zoom
            )
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }

    private func centerContent() {
        let bounds = scrollView.bounds.size
        let content = host.view.frame.size
        let offsetX = max((bounds.width - content.width) * 0.5, 0)
        let offsetY = max((bounds.height - content.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }
}
