import Carbon.HIToolbox
import Foundation

enum GlobalActivityShortcut: String, CaseIterable, Identifiable {
    case off
    case controlOptionA
    case controlOptionN

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .controlOptionA: "Control-Option-A"
        case .controlOptionN: "Control-Option-N"
        }
    }

    fileprivate var keyCode: UInt32? {
        switch self {
        case .off: nil
        case .controlOptionA: UInt32(kVK_ANSI_A)
        case .controlOptionN: UInt32(kVK_ANSI_N)
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .off: 0
        case .controlOptionA, .controlOptionN: UInt32(controlKey | optionKey)
        }
    }
}

/// Carbon remains the smallest permission-free bridge for a system-wide hotkey.
/// SwiftUI owns the preference; this object only registers the selected key and
/// forwards presses to the app's Activity Center action.
@MainActor
final class GlobalActivityShortcutController {
    private nonisolated(unsafe) var hotKey: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<GlobalActivityShortcutController>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    controller.action()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func configure(rawValue: String) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard let shortcut = GlobalActivityShortcut(rawValue: rawValue),
              let keyCode = shortcut.keyCode
        else { return }

        let identifier = EventHotKeyID(
            signature: OSType(0x414E4F54), // ANOT
            id: 1
        )
        RegisterEventHotKey(
            keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }
}
