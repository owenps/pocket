import AppKit
import Foundation
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct SettingsTests {
    @Test func optionalNameFieldEditsPreferenceAndTracksLiveChanges() throws {
        try withState { state in
            try withSettings(state: state) { host, window in
                try waitForLayout(host) { self.nameField(in: host) != nil }
                let field = try #require(nameField(in: host))
                #expect(field.stringValue.isEmpty)
                #expect(field.placeholderString?.isEmpty != false)
                #expect(window.makeFirstResponder(field))
                let editor = try #require(window.fieldEditor(false, for: field) as? NSTextView)
                editor.insertText("Owen", replacementRange: editor.selectedRange())
                try waitForLayout(host) { state.userName == "Owen" }
                editor.selectAll(nil)
                editor.insertText("", replacementRange: editor.selectedRange())
                try waitForLayout(host) { state.userName.isEmpty }
                #expect(window.makeFirstResponder(nil))
                state.userName = "Alex"
                try waitForLayout(host) { field.stringValue == "Alex" }
            }
        }
    }

    @Test func keepOpenToggleEditsPreferenceAndTracksLiveChanges() throws {
        try withState { state in
            try withSettings(state: state) { host, _ in
                @MainActor func toggle() -> NativeAccessibility? {
                    NativeAccessibility(host).descendant(identifier: "keepOpenWhenUnfocused")
                }
                try waitForLayout(host) { toggle()?.boolValue == false }
                let control = try #require(toggle())
                control.press()
                try waitForLayout(host) { state.keepOpenWhenUnfocused && toggle()?.boolValue == true }
                state.keepOpenWhenUnfocused = false
                try waitForLayout(host) { toggle()?.boolValue == false }
            }
        }
    }

    @Test func settingsDisplaysSavedShortcutAndTracksLiveChanges() throws {
        try withState { state in
            state.shortcut = .optionSpace
            try withSettings(state: state) { host, _ in
                try waitForLayout(host) { self.recorder(in: host)?.title == ShortcutChoice.optionSpace.title }
                state.shortcut = .controlSpace
                try waitForLayout(host) { self.recorder(in: host)?.title == ShortcutChoice.controlSpace.title }
                state.shortcut = .commandShiftSpace
                try waitForLayout(host) { self.recorder(in: host)?.title == ShortcutChoice.commandShiftSpace.title }
            }
        }
    }

    @Test(arguments: [UInt16(12), 13, 43])
    func recorderCapturesCommandCombinations(code: UInt16) throws {
        try withState { state in
            var recording: [Bool] = []
            try withSettings(state: state, recordingChanged: { recording.append($0) }) { host, _ in
                try waitForLayout(host) { self.recorder(in: host) != nil }
                let button = try #require(recorder(in: host))
                button.performClick(nil)
                #expect(recording == [true])
                let key = try #require([UInt16(12): "q", 13: "w", 43: ","][code])
                let event = try keyEvent(code: code, modifiers: .command, characters: key)
                #expect(button.performKeyEquivalent(with: event))
                let expected = try #require(ShortcutChoice(keyCode: code, modifiers: .command))
                #expect(state.shortcut == expected)
                #expect(recording == [true, false])
                try waitForLayout(host) { button.title == expected.title }
            }
        }
    }

    @Test func escapeCancelsRecordingWithoutChangingShortcut() throws {
        try withState { state in
            var recording: [Bool] = []
            try withSettings(state: state, recordingChanged: { recording.append($0) }) { host, _ in
                try waitForLayout(host) { self.recorder(in: host) != nil }
                let button = try #require(recorder(in: host))
                button.performClick(nil)
                button.keyDown(with: try keyEvent(code: 53, characters: "\u{1b}"))
                #expect(state.shortcut == .controlSpace)
                #expect(button.title == state.shortcut.title)
                #expect(recording == [true, false])
            }
        }
    }

    @Test func leavingRecorderRestoresShortcutWithoutChangingIt() throws {
        try withState { state in
            var recording: [Bool] = []
            try withSettings(state: state, recordingChanged: { recording.append($0) }) { host, window in
                try waitForLayout(host) { self.recorder(in: host) != nil }
                let button = try #require(recorder(in: host))
                button.performClick(nil)
                #expect(window.makeFirstResponder(nil))
                #expect(button.title == state.shortcut.title)
                #expect(recording == [true, false])
                button.performClick(nil)
                NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
                #expect(button.title == state.shortcut.title)
                #expect(recording == [true, false, true, false])
            }
        }
    }

    @Test func failedRecordedShortcutKeepsPreviousChoiceAndShowsError() throws {
        try withState { state in
            try withSettings(state: state, register: { _ in throw ShortcutConflict() }) { host, _ in
                try waitForLayout(host) { self.recorder(in: host) != nil }
                let button = try #require(recorder(in: host))
                button.performClick(nil)
                button.keyDown(with: try keyEvent(code: 40, modifiers: [.command, .option], characters: "k"))
                #expect(state.shortcut == .controlSpace)
                #expect(button.title == state.shortcut.title)
                try waitForLayout(host) {
                    guard let error = NativeAccessibility(host).descendant(identifier: "shortcutError") else { return false }
                    let visibleFrame = host.window?.convertToScreen(host.convert(host.bounds, to: nil)) ?? .zero
                    return error.text.contains(ShortcutConflict().localizedDescription)
                        && visibleFrame.intersects(error.frame)
                }
            }
        }
    }

    @Test func compactSettingsKeepEveryGeneralControlVisible() throws {
        try withState { state in
            state.fontSize = PanelState.fontSizeRange.upperBound
            try withSettings(state: state) { host, window in
                window.setContentSize(CGSize(width: 480, height: 600))
                let identifiers = ["userName", "launchAtLogin", "keepOpenWhenUnfocused", "fontSize", "fontPreview"]
                try waitForLayout(host) {
                    NativeAccessibility(host).descendant(identifier: "fontPreview")?.frame.isEmpty == false
                }
                let visibleFrame = window.convertToScreen(host.convert(host.bounds, to: nil))
                for identifier in identifiers {
                    let control = try #require(NativeAccessibility(host).descendant(identifier: identifier))
                    #expect(visibleFrame.contains(control.frame), "\(identifier) should be fully visible")
                }
                let button = try #require(recorder(in: host))
                let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
                #expect(!buttonFrame.isEmpty && visibleFrame.contains(buttonFrame))
            }
        }
    }

    @Test func minimumSettingsWidthProvidesTheTestedPreviewWidth() throws {
        try withState { state in
            state.fontSize = PanelState.fontSizeRange.upperBound
            try withSettings(state: state) { host, window in
                window.setContentSize(CGSize(width: 480, height: 720))
                try waitForLayout(host) {
                    (NativeAccessibility(host).descendant(identifier: "fontPreview")?.frame.width ?? 0) > 0
                }
                let preview = try #require(NativeAccessibility(host).descendant(identifier: "fontPreview"))
                #expect(preview.frame.width >= FontSizePreviewTests.minimumTestedWidth)
            }
        }
    }

    @Test func fontSliderAccessibilityActionsUpdatePreferenceAndTrackExternalChanges() throws {
        try withState { state in
            state.fontSize = 14
            try withSettings(state: state) { host, _ in
                try waitForLayout(host) { self.descendants(host).contains { $0 is NSSlider } }
                let slider = try #require(descendants(host).compactMap { $0 as? NSSlider }.first)
                _ = slider.accessibilityPerformIncrement()
                try waitForLayout(host) { state.fontSize == 15 }
                _ = slider.accessibilityPerformDecrement()
                try waitForLayout(host) { state.fontSize == 14 }
                let originalValue = slider.doubleValue
                state.fontSize = 22
                try waitForLayout(host) { slider.doubleValue != originalValue }
                _ = slider.accessibilityPerformIncrement()
                try waitForLayout(host) { state.fontSize == 23 }
                state.fontSize = PanelState.fontSizeRange.upperBound
                try waitForLayout(host) { slider.doubleValue == slider.maxValue }
                _ = slider.accessibilityPerformIncrement()
                #expect(state.fontSize == PanelState.fontSizeRange.upperBound)
            }
        }
    }

    private func withState(_ body: (PanelState) throws -> Void) throws {
        try withTestDefaults { defaults in
            let session = ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults)
            try body(PanelState(conversation: session, defaults: defaults))
        }
    }

    private func loginItem() -> LoginItemSettings {
        LoginItemSettings(status: { .notRegistered }, register: {}, unregister: {}, openSettings: {})
    }

    private func withSettings(
        state: PanelState,
        recordingChanged: @escaping (Bool) -> Void = { _ in },
        register: @escaping (ShortcutChoice) throws -> Void = { _ in },
        body: (NSView, NSWindow) throws -> Void
    ) throws {
        NativeAccessibility.enable()
        let host = NSHostingView(rootView: SettingsView(
            state: state, loginItem: loginItem(),
            changeShortcut: { state.changeShortcut(to: $0, register: register) },
            recordingChanged: recordingChanged
        ))
        let window = OffscreenTestWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.contentView = host
        defer { window.contentView = nil }
        try body(host, window)
    }

    private func nameField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        return view.subviews.lazy.compactMap { nameField(in: $0) }.first
    }

    private func recorder(in view: NSView) -> ShortcutRecorderButton? {
        if let button = view as? ShortcutRecorderButton { return button }
        return view.subviews.lazy.compactMap { recorder(in: $0) }.first
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func keyEvent(
        code: UInt16, modifiers: NSEvent.ModifierFlags = [], characters: String
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
    }

    private func waitForLayout(_ host: NSView, until condition: () -> Bool) throws {
        try NativeUITestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return condition()
        }
    }
}

private struct ShortcutConflict: LocalizedError {
    var errorDescription: String? { "That shortcut is already in use." }
}
