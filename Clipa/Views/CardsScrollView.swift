import SwiftUI
import AppKit

/// 原生横向滚动容器：鼠标滚轮(纵向)→横向 + 左键按住拖拽平移 + 键盘选中自动滚到可见。
struct CardsScrollView: NSViewRepresentable {
    let itemCount: Int
    var selectedIndex: Int
    var sensitivity: Double
    var onNearEnd: () -> Void = {}
    let content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator(onNearEnd: onNearEnd) }

    func makeNSView(context: Context) -> HPanScrollView {
        let scroll = HPanScrollView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .allowed
        scroll.automaticallyAdjustsContentInsets = false
        scroll.sensitivity = sensitivity
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = true
        scroll.documentView = host
        context.coordinator.scroll = scroll
        context.coordinator.installDragMonitor()
        context.coordinator.observeScroll(scroll)   // 滚到接近末尾 → 触发加载更多
        return scroll
    }

    func updateNSView(_ scroll: HPanScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        context.coordinator.onNearEnd = onNearEnd
        host.rootView = content
        scroll.sensitivity = sensitivity
        let clipH = scroll.contentView.bounds.height
        // 卡片等宽定高，宽度直接按数量算，省去 fittingSize 对全部卡片的一次额外整体布局。
        let width = itemCount > 0
            ? Theme.Space.lg * 2 + CGFloat(itemCount) * Theme.Card.width + CGFloat(itemCount - 1) * Theme.Card.spacing
            : 0
        let height = clipH > 0 ? clipH : Theme.Card.height + Theme.Space.md * 2
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        DispatchQueue.main.async { scrollToSelected(scroll) }
    }

    static func dismantleNSView(_ nsView: HPanScrollView, coordinator: Coordinator) {
        coordinator.removeObservers()
    }

    private func scrollToSelected(_ scroll: HPanScrollView) {
        let step = Theme.Card.width + Theme.Card.spacing
        let target = max(0, CGFloat(selectedIndex) * step - 60)
        let maxX = max(0, (scroll.documentView?.frame.width ?? 0) - scroll.contentView.bounds.width)
        scroll.contentView.scroll(to: NSPoint(x: min(target, maxX), y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    final class Coordinator {
        weak var scroll: HPanScrollView?
        var onNearEnd: () -> Void
        private var monitor: Any?
        private var boundsObserver: NSObjectProtocol?
        private var nearEndFired = false
        private var lastX: CGFloat = 0
        private var dragging = false

        init(onNearEnd: @escaping () -> Void) { self.onNearEnd = onNearEnd }

        /// 观察横向滚动，接近右端时触发一次 onNearEnd（滚离后重置，可再次触发→分批加载）。
        func observeScroll(_ scroll: HPanScrollView) {
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self, weak scroll] _ in
                guard let self, let scroll, let doc = scroll.documentView else { return }
                let visibleMaxX = scroll.contentView.bounds.maxX
                let contentWidth = doc.frame.width
                if visibleMaxX >= contentWidth - 500 {
                    if !self.nearEndFired { self.nearEndFired = true; self.onNearEnd() }
                } else if visibleMaxX < contentWidth - 800 {
                    self.nearEndFired = false
                }
            }
        }

        func removeObservers() {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            boundsObserver = nil
            removeDragMonitor()
        }

        func installDragMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
                guard let self, let scroll = self.scroll, let win = scroll.window, e.window === win else { return e }
                let pt = scroll.convert(e.locationInWindow, from: nil)
                let inside = scroll.bounds.contains(pt)
                switch e.type {
                case .leftMouseDown:
                    if inside { self.lastX = e.locationInWindow.x; self.dragging = false }
                    return e
                case .leftMouseDragged:
                    guard inside || self.dragging else { return e }
                    let dx = e.locationInWindow.x - self.lastX
                    self.lastX = e.locationInWindow.x
                    if abs(dx) > 2 { self.dragging = true }
                    if self.dragging { scroll.panBy(dx); return nil }   // 拖拽时吞掉，避免误选
                    return e
                case .leftMouseUp:
                    if self.dragging { self.dragging = false; return nil }
                    return e
                default: return e
                }
            }
        }

        func removeDragMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// 纵向滚轮→横向（带灵敏度）；支持代码平移。
final class HPanScrollView: NSScrollView {
    var sensitivity: Double = 3.5

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)   // 横向触控板手势走原生
            return
        }
        // 鼠标滚轮(非精确)每格 delta 很小，放大；触控板(精确)用原灵敏度
        let factor = event.hasPreciseScrollingDeltas ? sensitivity : sensitivity * 14
        panBy(event.scrollingDeltaY * factor)
    }

    /// 正 dx = 内容右移（看到更靠前的项）。
    func panBy(_ dx: CGFloat) {
        let maxX = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
        let newX = min(max(0, contentView.bounds.origin.x - dx), maxX)
        contentView.scroll(to: NSPoint(x: newX, y: 0))
        reflectScrolledClipView(contentView)
    }
}
