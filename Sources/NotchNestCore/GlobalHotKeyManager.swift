import Carbon.HIToolbox
import Foundation

/// Registers a system-wide Carbon hotkey (default: Option+Space) without needing Accessibility permissions.
@MainActor
public final class GlobalHotKeyManager {
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?
    private nonisolated(unsafe) var notificationObserver: NSObjectProtocol?
    private let onTrigger: @MainActor () -> Void

    private static let signature: OSType = 0x4E4E5354 // 'NNST'
    private static let hotKeyTriggeredNotification = Notification.Name("NotchNestGlobalHotKeyTriggered")

    public init(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    public func register(style: GlobalShortcutStyle) {
        let code: UInt32 = (style == .optionN) ? UInt32(kVK_ANSI_N) : UInt32(kVK_Space)
        register(keyCode: code, modifiers: UInt32(optionKey))
    }

    public func register(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey)
    ) {
        unregister()

        notificationObserver = NotificationCenter.default.addObserver(
            forName: Self.hotKeyTriggeredNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onTrigger()
            }
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, _ -> OSStatus in
                guard let eventRef else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalHotKeyManager.signature else {
                    return noErr
                }
                NotificationCenter.default.post(
                    name: GlobalHotKeyManager.hotKeyTriggeredNotification,
                    object: nil
                )
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        guard installStatus == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
    }
}
