import SwiftUI
import SwiftData
import Combine
import AppKit

/// 全局协调器：持有存储、设置与各服务，向视图发布剪贴板列表。
@MainActor
final class AppState: ObservableObject {
    let settings = AppSettings()
    let storage = StorageService()

    enum Segment: Equatable { case all, pinned, collection(UUID) }

    @Published var clips: [ClipItem] = []
    @Published var pinned: [ClipItem] = []
    @Published var collections: [ClipCollection] = []
    @Published var collectionClips: [ClipItem] = []
    @Published var searchText: String = "" { didSet { selectedIndex = 0; refresh() } }
    @Published var segment: Segment = .all { didSet { selectedIndex = 0; reloadCollectionClips() } }
    @Published var selectedIndex: Int = 0
    /// 每次唤出浮层自增，驱动搜索框重新聚焦（预热后 onAppear 不再触发，靠它保证聚焦）。
    @Published var searchFocusToken: Int = 0

    /// 当前浮层卡片行（受 segment 与搜索影响）。
    var visibleClips: [ClipItem] {
        switch segment {
        case .all: return clips
        case .pinned: return pinned
        case .collection: return collectionClips
        }
    }

    // 在后续里程碑接入：监听 / 快捷键 / 浮层 / 粘贴 / 内购
    private(set) lazy var monitor = ClipboardMonitor(storage: storage, settings: settings) { [weak self] in
        self?.refresh()
    }
    let paste = PasteService()
    private(set) lazy var hotKey = HotKeyService()
    private(set) lazy var panel = PanelController()
    let purchase = PurchaseService()

    private var onboardingWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // 转发设置变更：任何观察 appState 的视图（如卡片条）随设置实时更新
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        if AppSettings.commercialFeaturesEnabled {
            _ = TrialManager.shared    // 商业版首启即开始 2 个月试用计时（钥匙串持久）
        }
        settings.applyAppearance()
        cleanupHistory()
        refresh()
        monitor.start()
        hotKey.update(keyCode: UInt32(settings.hotKeyKeyCode),
                      carbonModifiers: UInt32(settings.hotKeyModifiers)) { [weak self] in
            self?.togglePanel()
        }
        Task { await purchase.refreshEntitlements(settings: settings) }
        maybeShowWelcome()

        // 启动后空闲时预热浮层，把首次唤出的构建成本挪到启动阶段。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.preload(appState: self)
        }
    }

    private lazy var welcomeWinDelegate = WindowCloseDelegate { [weak self] in
        NSApp.setActivationPolicy(.accessory)
        // 首启引导：欢迎窗关闭后自动弹出剪贴板浮层，让用户直观看到核心功能。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let self, !self.panel.isVisible else { return }
            self.panel.show(appState: self)
        }
    }

    private static let welcomeVersionKey = "lastWelcomeVersion"
    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// 首启或每次版本更新后展示欢迎页；商业版额外展示试用信息。
    func maybeShowWelcome() {
        // 记录上次弹欢迎页时的版本号：版本变化（含全新安装）才再弹一次。
        guard UserDefaults.standard.string(forKey: Self.welcomeVersionKey) != currentAppVersion else { return }
        UserDefaults.standard.set(currentAppVersion, forKey: Self.welcomeVersionKey)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = String(localized: "Welcome to Clipa")
        win.isReleasedWhenClosed = false
        win.center()
        let daysLeft = AppSettings.commercialFeaturesEnabled ? TrialManager.shared.daysRemaining : 0
        let view = WelcomeView(daysLeft: daysLeft,
                               onClose: { [weak self] in self?.onboardingWindow?.close() })
        win.contentView = NSHostingView(rootView: view)
        win.delegate = welcomeWinDelegate
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        onboardingWindow = win
    }

    func refresh() {
        clips = storage.fetchHistory(matching: searchText)
        pinned = storage.fetchPinned()
        collections = storage.fetchCollections()
        reloadCollectionClips()
    }

    /// 只重取当前所选集合的条目——切段位时用它，避免把 clips/pinned 又整体查一遍。
    private func reloadCollectionClips() {
        if case .collection(let id) = segment {
            collectionClips = storage.fetchItems(inCollection: id, matching: searchText)
        } else {
            collectionClips = []
        }
    }

    /// 按保留周期清理（启动 + 每次唤出浮层时调用）。
    func cleanupHistory() {
        storage.cleanup(maxItems: settings.effectiveMaxItems, retentionDays: settings.retentionPeriod.days)
    }

    func togglePanel() {
        panel.toggle(appState: self)
    }

    private var settingsWindow: NSWindow?
    private lazy var settingsWinDelegate = WindowCloseDelegate { [weak self] in
        self?.settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)   // 关闭后回到纯菜单栏
    }

    /// 打开偏好设置窗口（自管理 NSWindow，确保置顶不被遮挡）。
    func openSettings() {
        panel.hide()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = String(localized: "Settings")
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView:
            SettingsView().environmentObject(self).environmentObject(settings)
        )
        win.delegate = settingsWinDelegate
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    private var paywallWindow: NSWindow?
    private lazy var paywallWinDelegate = WindowCloseDelegate { [weak self] in
        self?.paywallWindow = nil
        if self?.settingsWindow == nil { NSApp.setActivationPolicy(.accessory) }
    }

    /// 打开 Pro 解锁窗口。
    func openPaywall() {
        guard AppSettings.commercialFeaturesEnabled else { return }
        panel.hide()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let win = paywallWindow { win.makeKeyAndOrderFront(nil); win.orderFrontRegardless(); return }

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = String(localized: "Clipa Pro")
        win.isReleasedWhenClosed = false
        win.center()
        let view = ProUnlockView(onClose: { [weak self] in self?.paywallWindow?.close() })
            .environmentObject(self).environmentObject(settings)
        win.contentView = NSHostingView(rootView: view)
        win.delegate = paywallWinDelegate
        paywallWindow = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    // MARK: - 键盘导航

    func moveSelection(_ delta: Int) {
        let count = visibleClips.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    func activateSelected() {
        let list = visibleClips
        guard list.indices.contains(selectedIndex) else { return }
        use(list[selectedIndex])
    }

    func selectByNumber(_ n: Int) {
        let idx = n - 1
        guard visibleClips.indices.contains(idx) else { return }
        selectedIndex = idx
        activateSelected()
    }

    /// 选用一条：回填剪贴板并（按设置）粘回前台 App。
    /// 立即回填剪贴板（保证马上 ⌘V 就能粘到），但把较重的存储保存与列表刷新
    /// 延后到收起动画之后——既避免动画卡顿，又避免连续点击时卡片在手下重排。
    func use(_ item: ClipItem, asPlainText: Bool = false) {
        let target = panel.previousApp
        // 自动粘贴暂时隐藏：强制使用手动 ⌘V 模式（忽略历史存储的 .auto 设置）。
        let cc = paste.paste(item, asPlainText: asPlainText, behavior: .manual, reactivating: target)
        monitor.suppressNextChange(cc)          // 忽略自身回填，避免额外触发一次刷新
        panel.hide()
        commitUsageAfterPanelHidden(item)
    }

    /// 右键「复制」：回填剪贴板、收起浮层；存储/刷新同样延后。
    func copy(_ item: ClipItem) {
        let cc = paste.copyOnly(item)
        monitor.suppressNextChange(cc)
        panel.hide()
        commitUsageAfterPanelHidden(item)
    }

    /// 收起动画（约 0.16s）之后再做 SwiftData 保存与列表刷新，避免阻塞动画首帧造成卡顿。
    private func commitUsageAfterPanelHidden(_ item: ClipItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.storage.touch(item)   // 移到最前（下次唤出即在最前）
            self.refresh()
        }
    }

    func togglePin(_ item: ClipItem) {
        guard storage.togglePin(item, maxPins: settings.effectiveMaxPins) else {
            openPaywall()   // 超出免费置顶上限：引导升级
            return
        }
        if item.isPinned { storage.touch(item) }   // 置顶后立即移到最前
        refresh()                                   // 立即刷新，让它马上跳到前面
    }

    func delete(_ item: ClipItem) {
        // 先从发布数组移除（SwiftUI 立刻撤掉该卡片），再延后删底层对象——
        // 否则卡片仍持有已删的 SwiftData 对象、下一帧访问其属性会崩（detached from a context）。
        let id = item.id
        clips.removeAll { $0.id == id }
        pinned.removeAll { $0.id == id }
        collectionClips.removeAll { $0.id == id }
        DispatchQueue.main.async { [weak self] in
            self?.storage.delete(item)
            self?.refresh()
        }
    }

    /// 清空全部历史：先收浮层 + 清空发布数组，让 SwiftUI 先移除所有卡片视图，
    /// 再延后删底层 SwiftData 对象。直接边删边渲染会触发 "detached from a context" 崩溃。
    func clearAllHistory() {
        panel.hide()
        clips = []
        pinned = []
        collectionClips = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.storage.clearAll()
            self.refresh()
        }
    }

    // MARK: - 集合

    var canCreateCollection: Bool {
        settings.isPro || collections.count < AppSettings.freeMaxCollections
    }

    /// 新建集合（可顺手把某条目存入）。用 NSAlert 取名，对无边框浮层最稳妥。
    func requestNewCollection(saving item: ClipItem? = nil) {
        guard canCreateCollection else { openPaywall(); return }   // 超出免费上限：引导升级
        guard let name = promptForName(title: String(localized: "New Collection"),
                                       message: String(localized: "Items saved to a collection are kept permanently and never removed by history cleanup. Name it, e.g. Prompts or Addresses."),
                                       initial: "",
                                       okTitle: String(localized: "Create")) else { return }
        let c = storage.createCollection(name: name)
        if let item { storage.setCollection(item, collectionID: c.id) }
        segment = .collection(c.id)   // 建完自动切过去（触发 refresh）
    }

    func requestRename(_ c: ClipCollection) {
        guard let name = promptForName(title: String(localized: "Rename Collection"),
                                       message: "", initial: c.name,
                                       okTitle: String(localized: "Save")) else { return }
        storage.renameCollection(c, to: name)
        refresh()
    }

    func confirmDeleteCollection(_ c: ClipCollection) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete this collection and its items?")
        alert.informativeText = c.name
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete Collection"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if segment == .collection(c.id) { segment = .all }   // 删掉当前集合则回到全部
        storage.deleteCollection(c)
        refresh()
    }

    /// 通用取名弹窗；返回去空白后的非空名字，取消或空则返回 nil。
    private func promptForName(title: String, message: String, initial: String, okTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if !message.isEmpty { alert.informativeText = message }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func addToCollection(_ item: ClipItem, _ collectionID: UUID) {
        storage.setCollection(item, collectionID: collectionID)
        refresh()
    }

    func removeFromCollection(_ item: ClipItem) {
        storage.setCollection(item, collectionID: nil)
        refresh()
    }

    // MARK: - 片段编辑器（独立窗口，沿用 Settings/Paywall 的窗口模式）

    private var snippetWindow: NSWindow?
    private lazy var snippetWinDelegate = WindowCloseDelegate { [weak self] in
        self?.snippetWindow = nil
        if self?.settingsWindow == nil, self?.paywallWindow == nil { NSApp.setActivationPolicy(.accessory) }
    }

    func openSnippetEditor(editing item: ClipItem? = nil, collectionID: UUID) {
        panel.hide()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = item == nil ? String(localized: "New Snippet") : String(localized: "Edit Snippet")
        win.isReleasedWhenClosed = false
        win.center()
        let view = SnippetEditorView(
            item: item,
            onSave: { [weak self] title, text in
                guard let self else { return }
                if let item { self.storage.updateSnippet(item, title: title, text: text) }
                else { self.storage.insertSnippet(title: title, text: text, collectionID: collectionID) }
                self.refresh()
                self.snippetWindow?.close()
            },
            onCancel: { [weak self] in self?.snippetWindow?.close() }
        )
        win.contentView = NSHostingView(rootView: view)
        win.delegate = snippetWinDelegate
        snippetWindow = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    // MARK: - 解压（Open With / 拖入触发）

    private var extractWindow: NSWindow?
    private lazy var extractWinDelegate = WindowCloseDelegate { [weak self] in
        self?.extractWindow = nil
        if self?.settingsWindow == nil, self?.paywallWindow == nil, self?.snippetWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// 处理 Finder 右键「用 Clipa…」/「打开方式」/ 拖入的文件：弹「压缩·解压」选择面板。
    func handleOpenFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        presentFileAction(urls)
    }

    /// Clipa 内部入口（菜单栏 / 浮层按钮）：不带文件，让用户在面板里拖入或选取。
    func openArchiveTool() {
        presentFileAction([])
    }

    // MARK: - 屏幕取色（系统吸管）

    private var colorSampler: NSColorSampler?

    /// 调系统吸管（NSColorSampler，整屏取色、无需额外权限）。
    /// 取到的颜色以 #RRGGBB 写入剪贴板——会被监听记录成一张 COLOR 卡片，随手可粘。
    func pickColor() {
        panel.hide()
        let sampler = NSColorSampler()
        colorSampler = sampler   // 采样期间持有，防止提前释放
        sampler.show { [weak self] color in
            self?.colorSampler = nil
            guard let color else { return }   // 用户按 Esc 取消
            let hex = AppState.hexString(from: color)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hex, forType: .string)
        }
    }

    static func hexString(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 复制一段纯文本到剪贴板，但抑制掉本次自造变更（不再新增一条历史）。
    func copyText(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        monitor.suppressNextChange(pb.changeCount)
    }

    // MARK: - 截屏（唤起系统截屏工具条，等同 ⌘⇧5，无需额外权限）

    func takeScreenshot() {
        panel.hide()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
        }
    }

    private func presentFileAction(_ urls: [URL]) {
        panel.hide()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let view = FileActionView(urls: urls, onClose: { [weak self] in self?.extractWindow?.close() })
        if let win = extractWindow {
            win.title = "Clipa"
            win.contentView = NSHostingView(rootView: view)
            win.makeKeyAndOrderFront(nil); win.orderFrontRegardless()
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Clipa"
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: view)
        win.delegate = extractWinDelegate
        extractWindow = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

#if DEBUG
    // MARK: - 调试开关（仅 Debug 编译，不进正式包）

    /// 重置版本标记并立即走一遍欢迎流程（含关闭后自动弹浮层），无需卸载重装。
    func debugSimulateFirstLaunch() {
        UserDefaults.standard.removeObject(forKey: Self.welcomeVersionKey)
        maybeShowWelcome()
    }

    /// 批量灌入示例条目，复现大列表、验证分批渲染与切换手感。
    func debugSeedSampleClips(_ n: Int) {
        storage.seedSampleClips(n)
        refresh()
    }
#endif
}

/// 通用窗口关闭回调代理。
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
