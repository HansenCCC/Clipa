import SwiftUI
import Carbon.HIToolbox

/// 录制全局快捷键的小控件。
struct ShortcutRecorder: View {
    @EnvironmentObject var appState: AppState
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press keys…" : display)
                .frame(minWidth: 120)
        }
        .onDisappear { stop() }
    }

    private var display: String {
        ShortcutFormatter.string(keyCode: appState.settings.hotKeyKeyCode,
                                 carbonModifiers: appState.settings.hotKeyModifiers)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let carbon = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
            guard carbon != 0 else { return nil } // 必须带修饰键
            appState.settings.hotKeyKeyCode = Int(event.keyCode)
            appState.settings.hotKeyModifiers = Int(carbon)
            appState.hotKey.update(keyCode: UInt32(event.keyCode), carbonModifiers: carbon) {
                appState.togglePanel()
            }
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

enum ShortcutFormatter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func string(keyCode: Int, carbonModifiers: Int) -> String {
        var s = ""
        if carbonModifiers & controlKey != 0 { s += "⌃" }
        if carbonModifiers & optionKey != 0 { s += "⌥" }
        if carbonModifiers & shiftKey != 0 { s += "⇧" }
        if carbonModifiers & cmdKey != 0 { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    private static func keyName(_ code: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_V: "V", kVK_ANSI_C: "C", kVK_ANSI_A: "A", kVK_Space: "Space",
            kVK_ANSI_X: "X", kVK_ANSI_Z: "Z", kVK_ANSI_B: "B", kVK_ANSI_D: "D",
        ]
        return map[code] ?? "Key\(code)"
    }
}
