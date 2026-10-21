import AppKit
import Carbon
import Testing
@testable import Pocket

@MainActor
struct ShortcutChoiceTests {
    @Test func legacyValuesRemainCompatible() {
        let presets: [(ShortcutChoice, String, String)] = [
            (.commandShiftSpace, "commandShiftSpace", "⌘⇧Space"),
            (.controlSpace, "controlSpace", "⌃Space"),
            (.optionSpace, "optionSpace", "⌥Space"),
        ]
        for (choice, rawValue, title) in presets {
            #expect(choice.rawValue == rawValue)
            #expect(ShortcutChoice(rawValue: rawValue) == choice)
            #expect(choice.title == title)
            #expect(choice.keyCode == UInt16(kVK_Space))
        }
    }

    @Test func customValueRoundTripsUsingStableKeyCodeAndModifierBits() throws {
        let choice = try #require(ShortcutChoice(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .option]))
        #expect(choice.rawValue == "40:1572864")
        #expect(ShortcutChoice(rawValue: choice.rawValue) == choice)
        #expect(Set([choice, try #require(ShortcutChoice(rawValue: choice.rawValue))]).count == 1)
    }

    @Test func modifiersAreNormalizedAndConvertedToCarbon() throws {
        let choice = try #require(ShortcutChoice(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: [.command, .control, .option, .shift, .capsLock, .function, .numericPad]
        ))
        #expect(choice.modifiers == [.command, .control, .option, .shift])
        #expect(choice.carbonModifiers == UInt32(cmdKey | controlKey | optionKey | shiftKey))
        #expect(ShortcutChoice(rawValue: choice.rawValue) == choice)
        #expect(ShortcutChoice(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift, .capsLock]) == .commandShiftSpace)
        #expect(ShortcutChoice(rawValue: "49:1179648") == .commandShiftSpace)
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .control, .option])
    func typingKeysRequireACommandModifier(_ modifier: NSEvent.ModifierFlags) {
        #expect(ShortcutChoice(keyCode: UInt16(kVK_ANSI_A), modifiers: modifier) != nil)
        #expect(ShortcutChoice(keyCode: UInt16(kVK_Space), modifiers: modifier) != nil)
        #expect(ShortcutChoice(keyCode: UInt16(kVK_LeftArrow), modifiers: modifier) != nil)
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .shift, .capsLock, .function, [.shift, .capsLock]])
    func bareTypingAndShiftOnlyAreRejected(_ modifiers: NSEvent.ModifierFlags) {
        for key in [kVK_ANSI_A, kVK_Space, kVK_Return, kVK_Tab, kVK_Delete, kVK_LeftArrow] {
            #expect(ShortcutChoice(keyCode: UInt16(key), modifiers: modifiers) == nil)
        }
    }

    @Test func allTwentyFunctionKeysWorkWithoutModifiers() throws {
        let keys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, key) in keys.enumerated() {
            let choice = try #require(ShortcutChoice(keyCode: UInt16(key), modifiers: []))
            #expect(choice.title == "F\(index + 1)")
            #expect(choice.carbonModifiers == 0)
            #expect(ShortcutChoice(rawValue: choice.rawValue) == choice)
        }
    }

    @Test func modifierKeysAndUndefinedKeyCodesAreRejected() {
        let invalid = [
            kVK_Command, kVK_RightCommand, kVK_Control, kVK_RightControl,
            kVK_Option, kVK_RightOption, kVK_Shift, kVK_RightShift, kVK_CapsLock, kVK_Function,
            0x34, 0x42, 0x44, 0x46, 0x4D, 0x6C, 0x70, 0x7F, 128, 255, 65535,
        ]
        for key in invalid {
            #expect(ShortcutChoice(keyCode: UInt16(key), modifiers: .command) == nil)
        }
    }

    @Test(arguments: ["", "unknown", "doubleTap:55", "40", "40:", ":1048576", "40:1048576:1", "-1:1048576", "65536:1048576", "40:no", "40:0", "56:1048576"])
    func malformedOrInvalidRawValuesAreRejected(_ rawValue: String) {
        #expect(ShortcutChoice(rawValue: rawValue) == nil)
    }

    @Test func specialKeysHaveReadableLabels() throws {
        for (key, label) in [(kVK_LeftArrow, "←"), (kVK_Return, "Return"), (kVK_Escape, "Esc"), (kVK_Tab, "Tab")] {
            let choice = try #require(ShortcutChoice(keyCode: UInt16(key), modifiers: .command))
            #expect(choice.title == "⌘" + label)
        }
        let ordinary = try #require(ShortcutChoice(keyCode: UInt16(kVK_ANSI_A), modifiers: .command))
        #expect(ordinary.title.hasPrefix("⌘"))
        #expect(ordinary.title.count > 1)
    }
}
