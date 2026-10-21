import Carbon
import Testing
@testable import Pocket

@MainActor
struct GlobalShortcutTests {
    @Test func enabledSystemShortcutConflictsWithMatchingKeyAndModifiers() {
        let entry: [String: Any] = [
            kHISymbolicHotKeyEnabled: true,
            kHISymbolicHotKeyCode: kVK_Space,
            kHISymbolicHotKeyModifiers: controlKey,
        ]
        #expect(GlobalShortcut.conflictsWithSystemShortcut(.controlSpace, hotKeys: [entry]))
        #expect(!GlobalShortcut.conflictsWithSystemShortcut(.optionSpace, hotKeys: [entry]))
        #expect(!GlobalShortcut.conflictsWithSystemShortcut(.commandShiftSpace, hotKeys: [entry]))
    }

    @Test func disabledDifferentAndMalformedSystemShortcutsDoNotConflict() {
        let entries: [[String: Any]] = [
            [kHISymbolicHotKeyEnabled: false, kHISymbolicHotKeyCode: kVK_Space, kHISymbolicHotKeyModifiers: controlKey],
            [kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: kVK_ANSI_A, kHISymbolicHotKeyModifiers: controlKey],
            [kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: kVK_Space, kHISymbolicHotKeyModifiers: controlKey | shiftKey],
            [kHISymbolicHotKeyEnabled: true, kHISymbolicHotKeyCode: kVK_Space],
            [:],
        ]
        #expect(!GlobalShortcut.conflictsWithSystemShortcut(.controlSpace, hotKeys: entries))
        #expect(!GlobalShortcut.conflictsWithSystemShortcut(.controlSpace, hotKeys: []))
    }

    @Test func customShortcutConflictsIgnoreNonShortcutModifierBits() throws {
        let choice = try #require(ShortcutChoice(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .option]))
        let entry: [String: Any] = [
            kHISymbolicHotKeyEnabled: true,
            kHISymbolicHotKeyCode: kVK_ANSI_K,
            kHISymbolicHotKeyModifiers: cmdKey | optionKey | alphaLock,
        ]
        #expect(GlobalShortcut.conflictsWithSystemShortcut(choice, hotKeys: [entry]))
    }
}
