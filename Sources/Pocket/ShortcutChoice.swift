import AppKit
import Carbon

struct ShortcutChoice: RawRepresentable, Hashable, CaseIterable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static let commandShiftSpace = ShortcutChoice(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift])!
    static let controlSpace = ShortcutChoice(keyCode: UInt16(kVK_Space), modifiers: .control)!
    static let optionSpace = ShortcutChoice(keyCode: UInt16(kVK_Space), modifiers: .option)!
    static let `default` = controlSpace

    /// Presets retained for callers that used the original enum.
    static let allCases: [ShortcutChoice] = [.commandShiftSpace, .controlSpace, .optionSpace]

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard Self.isOrdinaryKeyCode(keyCode) else { return nil }
        let modifiers = modifiers.intersection([.shift, .control, .option, .command])
        guard !modifiers.intersection([.command, .control, .option]).isEmpty
                || Self.functionKeys.contains(keyCode) else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(rawValue: String) {
        switch rawValue {
        case "commandShiftSpace": self = .commandShiftSpace
        case "controlSpace": self = .controlSpace
        case "optionSpace": self = .optionSpace
        default:
            let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let keyCode = UInt16(parts[0]),
                  let modifiers = UInt(parts[1]) else { return nil }
            self.init(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        }
    }

    // RawRepresentable's default equality compares rawValue, which itself matches presets.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    var rawValue: String {
        switch self {
        case .commandShiftSpace: "commandShiftSpace"
        case .controlSpace: "controlSpace"
        case .optionSpace: "optionSpace"
        default: "\(keyCode):\(modifiers.rawValue)"
        }
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    @MainActor var title: String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.command) { prefix += "⌘" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        return prefix + keyTitle
    }

    private static func isOrdinaryKeyCode(_ keyCode: UInt16) -> Bool {
        // Carbon's virtual-key table has holes and a contiguous block of modifier keys.
        keyCode <= kVK_UpArrow
            && !(0x36...0x3F).contains(keyCode)
            && ![0x34, 0x42, 0x44, 0x46, 0x4D, 0x6C, 0x70].contains(keyCode)
    }

    private static let functionKeys: [UInt16] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map(UInt16.init)

    private var keyTitle: String {
        if let index = Self.functionKeys.firstIndex(of: keyCode) { return "F\(index + 1)" }
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_ANSI_KeypadEnter: return "Enter"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_Help: return "Help"
        case kVK_ANSI_KeypadClear: return "Clear"
        case kVK_VolumeUp: return "Volume Up"
        case kVK_VolumeDown: return "Volume Down"
        case kVK_Mute: return "Mute"
        case kVK_ContextualMenu: return "Menu"
        case kVK_JIS_Eisu: return "英数"
        case kVK_JIS_Kana: return "かな"
        default: return translatedKeyTitle ?? "Key \(keyCode)"
        }
    }

    private var translatedKeyTitle: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 16)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
            characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
