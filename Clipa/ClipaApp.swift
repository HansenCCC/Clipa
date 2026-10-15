import SwiftUI
import SwiftData

@main
struct ClipaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 纯菜单栏入口（无 Dock 图标，见 Info.plist LSUIElement）
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appDelegate.appState)
        } label: {
            // 模板图：macOS 自动按菜单栏明暗反色（浅色栏→黑、深色栏→白），与系统图标一致。
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}
