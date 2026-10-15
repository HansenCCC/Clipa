import SwiftUI

/// 菜单栏下拉内容。
struct MenuBarContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button("Open Clipboard") { appState.togglePanel() }
            .keyboardShortcut("v", modifiers: [.command, .shift])

        // 自动粘贴功能暂时隐藏：仅支持手动粘贴，无需辅助功能权限提示。
        // 历史记录不在此展开——统一在浮层里查看，保持菜单精简。

        Divider()

        Button("Settings…") { appState.openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Pick Color…") { appState.pickColor() }
        Button("Screenshot…") { appState.takeScreenshot() }
        Button("Compress / Extract Files…") { appState.openArchiveTool() }

        Divider()
        Button("Quit Clipa") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
