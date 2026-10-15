import AppKit
import SwiftUI

/// 可成为 key 的无边框面板（否则搜索框无法输入）。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 管理底部非激活毛玻璃浮层（NSPanel）。
@MainActor
final class PanelController {
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var globalClickMonitor: Any?
    private weak var appState: AppState?
    /// 动画期间按目标显隐状态切换，避免收起尚未结束时吞掉新的打开请求。
    private var requestedVisible = false
    /// 新的显隐请求使旧动画完成回调失效。
    private var animationGeneration = 0
    /// 唤出浮层前的前台 App，用于粘贴时恢复焦点。
    private(set) var previousApp: NSRunningApplication?

    var isVisible: Bool { requestedVisible }

    func toggle(appState: AppState) {
        if requestedVisible { hide() } else { show(appState: appState) }
    }

    /// 启动时预热：提前创建面板并离屏渲染一次 SwiftUI 视图图，
    /// 避免首次唤出时才构建视图/加载图标缩略图导致 1~2s 卡顿。
    func preload(appState: AppState) {
        guard panel == nil else { return }
        self.appState = appState
        let panel = makePanel(appState: appState)
        self.panel = panel
        // 移到屏幕外、全透明地渲染一帧，强制建立视图树后再收起（用户不可见）。
        panel.setFrame(NSRect(x: -20000, y: -20000, width: 1200, height: Theme.Bar.panelHeight), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func show(appState: AppState) {
        requestedVisible = true
        animationGeneration &+= 1
        self.appState = appState
        previousApp = NSWorkspace.shared.frontmostApplication
        appState.searchText = ""
        appState.selectedIndex = 0
        appState.cleanupHistory()
        appState.refresh()
        appState.searchFocusToken &+= 1   // 触发搜索框聚焦（预热后 onAppear 不再触发）

        let panel = self.panel ?? makePanel(appState: appState)
        self.panel = panel
        positionAtBottom(panel)

        // 滑入 + 淡入
        let finalFrame = panel.frame
        var start = finalFrame
        start.origin.y -= 26
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }

        installKeyMonitor()
        installGlobalClickMonitor()
    }

    func hide() {
        guard requestedVisible else { return }
        requestedVisible = false
        animationGeneration &+= 1
        let hideGeneration = animationGeneration
        removeKeyMonitor()
        removeGlobalClickMonitor()
        guard let panel, panel.isVisible else { return }
        var down = panel.frame
        down.origin.y -= 26
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(down, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == hideGeneration, !self.requestedVisible else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    // MARK: - 键盘导航监听

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.appState else { return event }
            switch event.keyCode {
            case 53: self.hide(); return nil                       // esc
            case 123: state.moveSelection(-1); return nil          // ←
            case 124: state.moveSelection(1); return nil           // →
            case 36, 76: state.activateSelected(); return nil      // return / enter
            default:
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), (1...9).contains(n) {
                    state.selectByNumber(n)
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 点击浮层以外任何位置（其他 App / 桌面 / Dock）即收起。
    private func installGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeGlobalClickMonitor() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        globalClickMonitor = nil
    }

    // MARK: - 构建面板

    private func makePanel(appState: AppState) -> NSPanel {
        let height = Theme.Bar.panelHeight
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu   // 高于 Dock，唤出时覆盖 Dock
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.worksWhenModal = true

        let root = ClipBarPanel().environmentObject(appState)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func positionAtBottom(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        // 用整屏 frame（含 Dock 区域），贴最底 → 覆盖 Dock
        let full = screen.frame
        let height = panel.frame.height
        let frame = NSRect(x: full.minX, y: full.minY, width: full.width, height: height)
        panel.setFrame(frame, display: true)
    }
}
