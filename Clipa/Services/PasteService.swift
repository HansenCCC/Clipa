import AppKit
import Carbon.HIToolbox

/// 回填剪贴板 + 恢复前台 App + 模拟 ⌘V 自动粘贴。
@MainActor
final class PasteService {

    /// 系统是否已授予辅助功能权限。
    var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权请求（带提示）。
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 主流程

    /// 返回回填后剪贴板的 changeCount，供监听器忽略「我们自己造成的变更」（选用不重排）。
    @discardableResult
    func paste(_ item: ClipItem, asPlainText: Bool, behavior: PasteBehavior, reactivating app: NSRunningApplication? = nil) -> Int {
        let changeCount = writeToPasteboard(item, asPlainText: asPlainText)

        guard behavior == .auto, hasAccessibility else { return changeCount }

        // 恢复唤出前的前台 App，再模拟 ⌘V
        if let app {
            app.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postCommandV()
        }
        return changeCount
    }

    // MARK: - 回填剪贴板

    /// 回填剪贴板，返回写入后的 changeCount。
    @discardableResult
    func writeToPasteboard(_ item: ClipItem, asPlainText: Bool) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .image:
            if let path = item.imageFilePath, let img = ImageCache.shared.image(for: path) {
                pb.writeObjects([img])
            }
        case .file:
            let urls = item.fileURLs as [NSURL]
            if !urls.isEmpty { pb.writeObjects(urls) } else { pb.setString(item.plainText, forType: .string) }
        case .rtf:
            if !asPlainText, let rtf = item.rtfData {
                pb.setData(rtf, forType: .rtf)
                pb.setString(item.plainText, forType: .string)
            } else {
                pb.setString(item.plainText, forType: .string)
            }
        case .text, .link, .code, .color:
            pb.setString(item.plainText, forType: .string)
        }
        return pb.changeCount
    }

    /// 仅复制（不粘贴）。返回写入后的 changeCount。
    @discardableResult
    func copyOnly(_ item: ClipItem) -> Int {
        writeToPasteboard(item, asPlainText: false)
    }

    // MARK: - 模拟 ⌘V

    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        let loc = CGEventTapLocation.cghidEventTap
        down?.post(tap: loc)
        up?.post(tap: loc)
    }
}
