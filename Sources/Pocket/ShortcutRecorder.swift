import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: ShortcutChoice
    var onChange: (ShortcutChoice) -> Void
    var onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(frame: .zero)
    }

    func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
        view.shortcut = shortcut
        view.onChange = onChange
        view.onRecordingChanged = onRecordingChanged
    }

    static func dismantleNSView(_ view: ShortcutRecorderButton, coordinator: ()) {
        view.finishRecording()
        view.onChange = nil
        view.onRecordingChanged = nil
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: ShortcutChoice = .default {
        didSet { updateTitle() }
    }
    var onChange: ((ShortcutChoice) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var isRecording = false
    private weak var observedWindow: NSWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        setAccessibilityIdentifier("shortcutRecorder")
        setAccessibilityLabel("Show or hide Pocket shortcut")
        updateTitle()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        guard !isRecording, window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        onRecordingChanged?(true)
        updateTitle()
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChanged?(false)
        updateTitle()
    }

    private func updateTitle() {
        title = isRecording ? "Type shortcut…" : shortcut.title
        setAccessibilityValue(title)
        toolTip = isRecording ? "Press a shortcut. Escape cancels." : "Click to record a shortcut."
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53, modifiers.isEmpty {
            finishRecording()
        } else if !event.isARepeat {
            if let choice = ShortcutChoice(keyCode: event.keyCode, modifiers: modifiers) {
                accept(choice)
            } else {
                NSSound.beep()
            }
        }
    }

    private func accept(_ choice: ShortcutChoice) {
        // Restore first so a failed replacement leaves the working shortcut intact.
        finishRecording()
        onChange?(choice)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func cancelOperation(_ sender: Any?) { finishRecording() }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { finishRecording() }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
        }
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                name: NSWindow.didResignKeyNotification, object: window)
        } else {
            finishRecording()
        }
    }

    @objc private func windowResignedKey() { finishRecording() }
}
