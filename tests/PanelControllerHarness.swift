import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var searchText = ""
    @Published var selectedIndex = 0
    @Published var searchFocusToken = 0
    func cleanupHistory() {}
    func refresh() {}
    func moveSelection(_ delta: Int) { selectedIndex += delta }
    func activateSelected() {}
    func selectByNumber(_ number: Int) { selectedIndex = number - 1 }
}

struct ClipBarPanel: View {
    var body: some View { Color.clear.frame(width: 1200, height: Theme.Bar.panelHeight) }
}

enum Theme {
    enum Bar { static let panelHeight: CGFloat = 180 }
}

@main
@MainActor
struct PanelControllerHarness {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        let controller = PanelController()
        let panel = controller

        panel.show(appState: state)
        check(panel.isVisible, "show sets logical visibility immediately")
        let nativePanel = onlyHarnessPanel(app)
        check(nativePanel.isVisible, "show orders native panel front")

        panel.hide()
        check(!panel.isVisible, "hide clears logical visibility immediately")
        panel.show(appState: state)
        check(panel.isVisible, "show immediately after hide restores logical visibility")
        pump(0.45)
        check(nativePanel.isVisible, "old hide completion cannot order out a newer show")

        panel.hide()
        panel.hide()
        check(!panel.isVisible, "repeated hide is idempotent")
        pump(0.35)
        check(!nativePanel.isVisible, "final hide orders native panel out")

        panel.toggle(appState: state)
        check(panel.isVisible, "toggle opens")
        panel.toggle(appState: state)
        check(!panel.isVisible, "toggle closes immediately")
        panel.toggle(appState: state)
        check(panel.isVisible, "continuous toggle reopens")
        pump(0.45)
        check(nativePanel.isVisible, "continuous toggle leaves native panel visible")
        panel.hide()
        pump(0.35)
        check(!panel.isVisible && !nativePanel.isVisible, "cleanup hide completes")
        print("PASS panel show-hide-generation-toggle")
        app.terminate(nil)
    }

    static func onlyHarnessPanel(_ app: NSApplication) -> NSPanel {
        guard let panel = app.windows.compactMap({ $0 as? NSPanel }).first else {
            fputs("FAIL native panel was not created\n", stderr)
            exit(1)
        }
        return panel
    }

    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func check(_ condition: Bool, _ name: String) {
        guard condition else { fputs("FAIL \(name)\n", stderr); exit(1) }
        print("PASS \(name)")
    }
}
