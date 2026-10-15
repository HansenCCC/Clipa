import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
        if ScreenshotRenderer.runIfRequested() { return }
        #endif
        appState.start()
        AppTracker.shared.track()
        ReviewManager.shared.registerLaunchAndMaybePrompt()
    }

    /// Finder 右键「用 Clipa…」/「打开方式」/ 双击 / 拖入的文件都会到这里。
    func application(_ application: NSApplication, open urls: [URL]) {
        appState.handleOpenFiles(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.monitor.stop()
    }
}
