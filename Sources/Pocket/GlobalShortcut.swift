import Carbon

/// Carbon hotkeys work globally without observing everything the user types.
@MainActor
final class GlobalShortcut {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registeredChoice: ShortcutChoice?
    private let onPressed: @MainActor () -> Void

    init(onPressed: @escaping @MainActor () -> Void) throws {
        self.onPressed = onPressed
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                    if shortcut.hotKey != nil { shortcut.onPressed() }
                }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { throw RegistrationError(status: status) }
    }

    func register(_ choice: ShortcutChoice) throws {
        guard registeredChoice != choice || hotKey == nil else { return }
        var symbolicHotKeys: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&symbolicHotKeys) == noErr,
           let keys = symbolicHotKeys?.takeRetainedValue() as? [[String: Any]],
           Self.conflictsWithSystemShortcut(choice, hotKeys: keys) {
            throw RegistrationError(status: OSStatus(eventHotKeyExistsErr))
        }
        var newHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(choice.keyCode), choice.carbonModifiers,
            EventHotKeyID(signature: 0x504F434B, id: 1),
            GetApplicationEventTarget(), 0, &newHotKey
        )
        guard status == noErr else { throw RegistrationError(status: status) }
        suspend()
        hotKey = newHotKey
        registeredChoice = choice
    }

    static func conflictsWithSystemShortcut(_ choice: ShortcutChoice, hotKeys: [[String: Any]]) -> Bool {
        hotKeys.contains { key in
            guard let enabled = key[kHISymbolicHotKeyEnabled] as? NSNumber,
                  enabled.boolValue,
                  let code = key[kHISymbolicHotKeyCode] as? NSNumber,
                  let modifiers = key[kHISymbolicHotKeyModifiers] as? NSNumber else { return false }
            let mask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
            return code.uint32Value == UInt32(choice.keyCode)
                && modifiers.uint32Value & mask == choice.carbonModifiers
        }
    }

    func suspend() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    func stop() {
        suspend()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        registeredChoice = nil
    }

    struct RegistrationError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            if status == eventHotKeyExistsErr {
                return "That shortcut is already in use. Choose another shortcut in Pocket Settings."
            }
            return "Couldn't register the shortcut (macOS error \(status)). "
                + "Choose another shortcut in Pocket Settings."
        }
    }
}
