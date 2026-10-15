import AppKit
import Carbon.HIToolbox

/// 基于 Carbon RegisterEventHotKey 的全局快捷键（无三方依赖）。
final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    private let signature: OSType = 0x434C5041  // 'CLPA'

    /// 注册/更新快捷键。carbonModifiers 为 Carbon 修饰键掩码（cmdKey/shiftKey…）。
    func update(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        unregister()

        installEventHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let mods = carbonModifiers == 0 ? UInt32(cmdKey | shiftKey) : carbonModifiers
        RegisterEventHotKey(keyCode, mods, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        _ = hotKeyID
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.signature == service.signature {
                DispatchQueue.main.async { service.handler?() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
